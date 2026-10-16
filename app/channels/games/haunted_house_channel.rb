class Games::HauntedHouseChannel < ApplicationCable::Channel
  STREAM_PREFIX = "haunted_house_room_"

  # Seconds each phase lasts. The night and the vote end early once everyone has acted; the host
  # can skip the discussion (its length is a room setting).
  ROLES_DURATION   = 10
  NIGHT_DURATION   = 30
  MORNING_DURATION = 7
  VOTE_DURATION    = 30
  VERDICT_DURATION = 7
  GRACE_PERIOD     = 1    # after a timer runs out, for taps still on their way
  EARLY_END_DELAY  = 1.5  # after the last player acts, so their tap shows before the phase moves on
  POLL_INTERVAL    = 0.25
  # The loop writes a heartbeat; a loop silent for this long is dead (e.g. the server restarted),
  # so the TV may start a new one.
  LOOP_TIMEOUT = 10

  def subscribed
    @room   = Room.find_by(code: params[:room_code])
    @player = find_player
    return if subscription_rejected?

    track_player_subscribed(@player)
    stream_from room_stream
    # Each screen's own view of every phase: the TV's has no secrets, a phone's has its role (and a
    # ghost's the other ghosts' picks).
    stream_from host? ? host_stream : player_stream(@player.id)

    sync
  end

  def unsubscribed
    track_player_unsubscribed(@player)
  end

  # Sends this screen everything it may see right now: on connecting (a phone that loads late, or
  # reloads, joins the current phase) and when a phone asks again (e.g. after a player left).
  def sync(_data = nil)
    @room.reload
    svc = service
    transmit({ action: "state", state: host? ? svc.host_state : svc.player_state(@player.id), nicknames: nicknames_map })
  end

  # ── Host actions ──────────────────────────────────────────────────────────

  def start_game_loop(_data = nil)
    return unless host?

    loop_id = claim_loop
    return unless loop_id

    Thread.new do
      run_game(loop_id)
    rescue => e
      Rails.logger.error("[HauntedHouseChannel] game loop crashed in room #{@room&.code}: #{e.message}\n#{e.backtrace.first(3).join("\n")}")
      broadcast({ action: "game_error" }) rescue nil
      @room&.update!(status: "finished") rescue nil
    end
  end

  def skip_discussion(_data = nil)
    return unless host?

    service.skip!
  end

  # Play Again: new roles, same settings. Clears the loop id, so a loop still running stops.
  def restart_game(_data = nil)
    return unless host?

    @room = Room.find_by(code: params[:room_code])
    GameServices::HauntedHouse.new(@room).setup_game!
    broadcast({ action: "game_restarted" })
  end

  # ── Player actions ────────────────────────────────────────────────────────

  def ghost_pick(data)
    return unless @player

    svc = service
    return unless svc.ghost_pick!(@player.id, data["target_id"])

    @room.reload
    picks = @room.game_state["ghost_picks"].to_h
    ghost_ids(@room).each { |id| ActionCable.server.broadcast(player_stream(id), { action: "ghost_picks", ghost_picks: picks }) }
    broadcast_acted(svc)
  end

  def medium_check(data)
    return unless @player

    svc    = service
    result = svc.medium_check!(@player.id, data["target_id"])
    return unless result

    transmit({ action: "medium_result", target_id: data["target_id"].to_s, ghost: result[:ghost] })
    broadcast_acted(svc)
  end

  def hide(data)
    return unless @player

    svc = service
    return unless svc.hide!(@player.id, data["place"])

    transmit({ action: "hidden", place: data["place"].to_s })
    broadcast_acted(svc)
  end

  def vote(data)
    return unless @player

    svc = service
    return unless svc.vote!(@player.id, data["target_id"])

    transmit({ action: "voted", target_id: data["target_id"].to_s })
    broadcast({ action: "acted", acted: svc.voted })
  end

  private

  # Roles → night → morning → discussion → vote → verdict → night … until a team wins.
  def run_game(loop_id)
    svc = GameServices::HauntedHouse.new(Room.find_by(code: params[:room_code]))

    phase(svc, loop_id, ROLES_DURATION) { svc.start_roles!(ROLES_DURATION) } or return

    until svc.winner
      phase(svc, loop_id, NIGHT_DURATION, early: -> { svc.night_done? }) { svc.start_night!(NIGHT_DURATION) } or return
      svc.end_night!
      phase(svc, loop_id, MORNING_DURATION) or return
      break if svc.winner

      discussion = svc.room.game_state["discussion_time"].to_i
      phase(svc, loop_id, discussion, early: -> { svc.skipped?("discussion") }) { svc.start_discussion!(discussion) } or return
      phase(svc, loop_id, VOTE_DURATION, early: -> { svc.all_voted? }) { svc.start_vote!(VOTE_DURATION) } or return
      svc.end_vote!
      phase(svc, loop_id, VERDICT_DURATION) or return
    end

    return unless current_loop?(loop_id)

    svc.finish_game!
    send_state(svc)
  end

  # Starts a phase (the block), tells every screen, then waits for its timer, for `early`, for a
  # winner (a player leaving can end the game at any time) or for the loop to be replaced.
  # Returns false when the loop must stop.
  def phase(svc, loop_id, seconds, early: nil)
    yield if block_given?
    send_state(svc)
    decided = svc.winner # a morning or verdict that settles the game still shows in full

    deadline = monotonic_now + seconds + GRACE_PERIOD
    while monotonic_now < deadline
      return false unless current_loop?(loop_id)
      break if !decided && svc.winner
      if early&.call
        sleep EARLY_END_DELAY
        break
      end

      sleep POLL_INTERVAL
    end
    current_loop?(loop_id)
  end

  # Every screen gets the new phase on its own stream: the TV without secrets, each phone with
  # what only it may see (its role, the ghosts' picks, the Medium's checks).
  def send_state(svc)
    room = svc.room.reload
    nicknames = nicknames_map(room)
    ActionCable.server.broadcast(host_stream, { action: "state", state: svc.host_state, nicknames: nicknames })
    room.players.each do |player|
      ActionCable.server.broadcast(player_stream(player.id), { action: "state", state: svc.player_state(player.id), nicknames: nicknames })
    end
  end

  def broadcast_acted(svc)
    broadcast({ action: "acted", acted: svc.acted_tonight })
  end

  # One loop per game, whichever TV connection started it. Takes over when there's no loop or the
  # last one stopped writing its heartbeat. Returns the new loop id, or nil when one is running.
  def claim_loop
    loop_id = SecureRandom.hex(6)
    stale   = Time.now.to_f - LOOP_TIMEOUT
    claimed = Room.collection.update_one(
      { "code" => params[:room_code], "status" => "playing",
        "$or" => [ { "game_state.loop_id" => nil }, { "game_state.loop_beat" => { "$lt" => stale } } ] },
      { "$set" => { "game_state.loop_id" => loop_id, "game_state.loop_beat" => Time.now.to_f } }
    )
    claimed.modified_count == 1 ? loop_id : nil
  end

  # True while this loop is still the room's loop (Play Again or a takeover replaces it). Also
  # writes the heartbeat.
  def current_loop?(loop_id)
    Room.collection.update_one(
      { "code" => params[:room_code], "status" => "playing", "game_state.loop_id" => loop_id },
      { "$set" => { "game_state.loop_beat" => Time.now.to_f } }
    ).matched_count == 1
  end

  def ghost_ids(room)
    room.game_state["roles"].to_h.select { |_, role| role == GameServices::HauntedHouse::GHOST }.keys
  end

  def service
    GameServices::HauntedHouse.new(@room.reload)
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
