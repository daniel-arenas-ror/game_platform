class Games::MonsterMashChannel < ApplicationCable::Channel
  include ApplicationCable::ClaimedLoop

  STREAM_PREFIX = "monster_mash_room_"

  # Seconds each phase lasts. Drawing rounds use the room's setting and end early once everyone
  # taps Done; the vote ends once everyone has voted. The host can skip a reveal or the results.
  THEME_DURATION   = 8
  PASS_DURATION    = 4  # between drawing rounds: "pass the monster on"
  REVEAL_EACH      = 9  # per monster
  VOTE_DURATION    = 40
  RESULTS_DURATION = 12
  GRACE_PERIOD     = 1.5 # after a drawing timer runs out, for strokes still on their way
  EARLY_END_DELAY  = 1
  POLL_INTERVAL    = 0.25

  def subscribed
    @room   = Room.find_by(code: params[:room_code])
    @player = find_player
    return if subscription_rejected?

    track_player_subscribed(@player)
    stream_from room_stream
    # Each screen's own view of every phase: a phone's includes what it is drawing.
    stream_from host? ? host_stream : player_stream(@player.id)

    sync
  end

  def unsubscribed
    track_player_unsubscribed(@player)
  end

  # Everything this screen may see right now: on connecting (a late or reloaded phone joins the
  # current phase, with its drawing so far) and when a screen asks again. At the reveal it also
  # gets the monster on show; from the vote on, every monster.
  def sync(_data = nil)
    @room.reload
    svc   = service
    state = @room.game_state
    transmit({ action: "state", state: host? ? svc.host_state : svc.player_state(@player.id), nicknames: nicknames_map })
    transmit({ action: "monster", monster: svc.monster(state["reveal_index"]) }) if state["phase"] == "reveal" && state["reveal_index"].to_i >= 0
    # The vote and the results show every monster: a screen that missed the reveal gets them all.
    transmit({ action: "gallery", monsters: svc.gallery }) if %w[vote results game_over].include?(state["phase"])
  end

  # ── Host actions ──────────────────────────────────────────────────────────

  def start_game_loop(_data = nil)
    return unless host?

    loop_id = claim_loop
    return unless loop_id

    Thread.new do
      run_game(loop_id)
    rescue => e
      Rails.logger.error("[MonsterMashChannel] game loop crashed in room #{@room&.code}: #{e.message}\n#{e.backtrace.first(3).join("\n")}")
      broadcast({ action: "game_error" }) rescue nil
      @room&.update!(status: "finished") rescue nil
    end
  end

  # Moves on from the monster on show (or from the results).
  def skip(_data = nil)
    return unless host?

    service.skip!
  end

  def restart_game(_data = nil)
    return unless host?

    @room = Room.find_by(code: params[:room_code])
    GameServices::MonsterMash.new(@room).setup_game!
    broadcast({ action: "game_restarted" })
  end

  # ── Player actions ────────────────────────────────────────────────────────

  # A finished stroke: { id:, points: [[x, y], …], color:, size: }. Saved at once, so nothing is
  # lost when time runs out. Never shown on the TV until the reveal.
  def stroke_end(data)
    return unless @player

    id     = GameServices::DoodleDash.clean_stroke_id(data["id"])
    points = GameServices::DoodleDash.clean_points(data["points"], GameServices::MonsterMash::MAX_STROKE_POINTS)
    style  = GameServices::DoodleDash.clean_style(data["color"], data["size"])
    return unless id && points && style

    service.save_stroke!(@player.id, style.merge("id" => id, "points" => points))
  end

  def undo(data)
    id = GameServices::DoodleDash.clean_stroke_id(data["id"])
    service.undo!(@player.id, id) if @player && id
  end

  def clear(data)
    upto = GameServices::DoodleDash.clean_stroke_id(data["upto"])
    service.clear!(@player.id, upto) if @player && upto
  end

  def done(_data = nil)
    return unless @player

    svc = service
    return unless svc.done!(@player.id)

    transmit({ action: "done_ok" })
    broadcast({ action: "progress", ids: svc.done_ids })
  end

  def vote(data)
    return unless @player

    svc = service
    return unless svc.vote!(@player.id, data["index"])

    transmit({ action: "voted", index: data["index"].to_i })
    broadcast({ action: "progress", ids: svc.voted_ids })
  end

  # A phone's gallery at the end, to screenshot a favourite.
  def gallery(_data = nil)
    @room.reload
    transmit({ action: "gallery", monsters: service.gallery }) if @room.game_state["phase"] == "game_over"
  end

  private

  # Theme → heads → bodies → legs → reveal each monster → vote → results → game over.
  def run_game(loop_id)
    svc = GameServices::MonsterMash.new(Room.find_by(code: params[:room_code]))

    phase(svc, loop_id, THEME_DURATION) { svc.start_interlude!("theme", THEME_DURATION) } or return

    draw_time = svc.room.game_state["draw_time"].to_i
    GameServices::MonsterMash::PARTS.each_index do |round|
      if round.positive?
        phase(svc, loop_id, PASS_DURATION) { svc.start_interlude!("passing", PASS_DURATION) } or return
      end
      phase(svc, loop_id, draw_time + GRACE_PERIOD, early: -> { svc.all_done? }) { svc.start_round!(round, draw_time) } or return
    end

    svc.start_reveal!
    svc.monsters_count.times do |index|
      monster = svc.reveal!(index)
      phase(svc, loop_id, REVEAL_EACH, early: -> { svc.skipped? }) do
        svc.room.atomic_set("game_state.skip" => nil)
        broadcast({ action: "monster", monster: monster })
      end or return
    end

    phase(svc, loop_id, VOTE_DURATION, early: -> { svc.all_voted? }) { svc.start_vote!(VOTE_DURATION) } or return
    svc.end_vote!
    phase(svc, loop_id, RESULTS_DURATION, early: -> { svc.skipped? }) or return

    return unless current_loop?(loop_id)

    svc.finish_game!
    send_state(svc)
    ActionCable.server.broadcast(host_stream, { action: "gallery", monsters: svc.gallery })
  end

  # Starts a phase (the block), tells every screen, then waits for its timer, for `early` or for
  # the loop to be replaced. Returns false when the loop must stop.
  def phase(svc, loop_id, seconds, early: nil)
    return false unless current_loop?(loop_id) # Play Again may have replaced this loop meanwhile

    yield if block_given?
    send_state(svc)

    deadline = monotonic_now + seconds
    while monotonic_now < deadline
      return false unless current_loop?(loop_id)
      if early&.call
        sleep EARLY_END_DELAY
        break
      end

      sleep POLL_INTERVAL
    end
    current_loop?(loop_id)
  end

  # Every screen gets the phase on its own stream: the TV without drawings, each phone with its task.
  def send_state(svc)
    room = svc.room.reload
    nicknames = nicknames_map(room)
    ActionCable.server.broadcast(host_stream, { action: "state", state: svc.host_state, nicknames: nicknames })
    room.players.each do |player|
      ActionCable.server.broadcast(player_stream(player.id), { action: "state", state: svc.player_state(player.id), nicknames: nicknames })
    end
  end

  def service
    GameServices::MonsterMash.new(@room.reload)
  end

  def host?
    @player.nil?
  end

  def room_stream
    "#{STREAM_PREFIX}#{@room.code}"
  end

  def host_stream
    "#{STREAM_PREFIX}#{@room.code}_host"
  end

  def player_stream(player_id)
    "#{STREAM_PREFIX}#{@room.code}_player_#{player_id}"
  end

  def broadcast(payload)
    ActionCable.server.broadcast(room_stream, payload)
  end

  def nicknames_map(room = @room)
    room.players.to_h { |p| [ p.id.to_s, p.nickname ] }
  end

  def monotonic_now
    Process.clock_gettime(Process::CLOCK_MONOTONIC)
  end
end
