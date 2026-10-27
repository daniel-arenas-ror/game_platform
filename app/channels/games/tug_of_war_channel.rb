class Games::TugOfWarChannel < ApplicationCable::Channel
  include ApplicationCable::ClaimedLoop

  STREAM_PREFIX = "tug_of_war_room_"

  # Seconds each phase lasts. The teams screen waits for the host's Start pulling; the pulling uses
  # the room's time limit (or none) and ends as soon as the rope reaches an end; the host can skip
  # the round-over screen.
  COUNTDOWN_DURATION  = 3
  ROUND_OVER_DURATION = 8
  GRACE_PERIOD        = 0.5 # after the time limit, for answers still on their way
  EARLY_END_DELAY     = 0.8 # so the winning pull shows before the round-over screen
  POLL_INTERVAL       = 0.25

  def subscribed
    @room   = Room.find_by(code: params[:room_code])
    @player = find_player
    return if subscription_rejected?

    track_player_subscribed(@player)
    stream_from room_stream
    stream_from player_stream(@player.id) if @player

    join_team if @player
    sync
  end

  def unsubscribed
    track_player_unsubscribed(@player)
  end

  # Everything this screen may see right now (a phone also gets its team, its problem and its
  # freeze): on connecting and whenever a screen asks again.
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
      Rails.logger.error("[TugOfWarChannel] game loop crashed in room #{@room&.code}: #{e.message}\n#{e.backtrace.first(3).join("\n")}")
      broadcast({ action: "game_error" }) rescue nil
      @room&.update!(status: "finished") rescue nil
    end
  end

  # Moves a player to the other team (or to { team: "red" | "blue" }) on the teams screen.
  def move_player(data)
    return unless host?

    svc = service
    send_teams(svc) if svc.move_player!(data["player_id"], data["team"])
  end

  def shuffle_teams(_data = nil)
    return unless host?

    svc = service
    send_teams(svc) if svc.shuffle_teams!
  end

  # Ends the teams screen; the loop starts the first round.
  def start_pulling(_data = nil)
    return unless host?

    service.request_start!
  end

  # Moves on from the round-over screen.
  def skip(_data = nil)
    return unless host?

    service.skip!
  end

  def restart_game(_data = nil)
    return unless host?

    @room = Room.find_by(code: params[:room_code])
    GameServices::TugOfWar.new(@room).setup_game!
    broadcast({ action: "game_restarted" })
  end

  # ── Player actions ────────────────────────────────────────────────────────

  # { problem_id:, value:, id: } — id is the phone's, to match the result. The phone gets the
  # result (with its next problem); everyone sees pulls and freezes.
  def answer(data)
    return unless @player

    svc    = GameServices::TugOfWar.new(@room)
    result = svc.answer!(@player.id, data["problem_id"], data["value"])
    transmit({ action: "answer_result", id: data["id"] }.merge(result))

    pid = @player.id.to_s
    case result["result"]
    when "correct"
      broadcast({ action: "pull", player_id: pid }
                  .merge(result.slice("team", "step", "position", "pulls", "team_pulls", "streak", "won")))
    when "wrong"
      broadcast({ action: "frozen", player_id: pid, seconds: result["seconds"] })
    end
  end

  private

  # A phone that isn't on a team yet (joined after the start) goes to the smaller one; the other
  # screens hear about it.
  def join_team
    svc = service
    return if svc.room.game_state["teams"].to_h.key?(@player.id.to_s)

    send_teams(svc) if svc.join!(@player.id)
  end

  # Teams screen → for each round: countdown → pulling → round over. Then game over.
  def run_game(loop_id)
    svc = GameServices::TugOfWar.new(Room.find_by(code: params[:room_code]))
    svc.loop_id = loop_id
    total = svc.room.game_state["total_rounds"].to_i
    limit = svc.room.game_state["time_limit"].to_i

    phase(svc, loop_id, Float::INFINITY, early: -> { svc.start_requested? }, delay: 0) or return

    (1..total).each do |round|
      phase(svc, loop_id, COUNTDOWN_DURATION) { svc.start_round!(round, COUNTDOWN_DURATION) && send_problems(svc) } or return
      pulling = limit.positive? ? limit + GRACE_PERIOD : Float::INFINITY
      phase(svc, loop_id, pulling, early: -> { svc.round_won? }) { svc.start_pulling! } or return
      svc.time_up!
      phase(svc, loop_id, ROUND_OVER_DURATION, early: -> { svc.skipped? }) { svc.end_round!(ROUND_OVER_DURATION) } or return
      break if svc.last_round?
    end

    return unless current_loop?(loop_id)

    svc.finish_game!
    send_state(svc)
  end

  # Starts a phase (the block), tells every screen, then waits for its timer, for `early` or for
  # the loop to be replaced. Returns false when the loop must stop.
  def phase(svc, loop_id, seconds, early: nil, delay: EARLY_END_DELAY)
    return false unless current_loop?(loop_id) # Play Again may have replaced this loop meanwhile

    yield if block_given?
    send_state(svc)

    deadline = monotonic_now + seconds
    while monotonic_now < deadline
      return false unless current_loop?(loop_id)
      if early&.call
        sleep delay
        break
      end

      sleep POLL_INTERVAL
    end
    current_loop?(loop_id)
  end

  # The TV and the phones see the same state; a phone's own problem goes to it alone.
  def send_state(svc)
    room = svc.room.reload
    broadcast({ action: "state", state: svc.public_state, nicknames: nicknames_map(room) })
  end

  def send_problems(svc)
    room = svc.room.reload
    room.game_state["problems"].to_h.each do |pid, problem|
      ActionCable.server.broadcast(player_stream(pid), { action: "problem", round: room.game_state["round"],
                                                         problem: GameServices::TugOfWar::Problems.shown(problem) })
    end
  end

  def send_teams(svc)
    room  = svc.room.reload
    state = svc.public_state
    broadcast({ action: "teams", teams: state["teams"], team_sizes: state["team_sizes"], nicknames: nicknames_map(room) })
  end

  def service
    GameServices::TugOfWar.new(@room.reload)
  end

  def host?
    @player.nil?
  end

  def room_stream
    "#{STREAM_PREFIX}#{@room.code}"
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
