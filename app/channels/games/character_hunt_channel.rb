class Games::CharacterHuntChannel < ApplicationCable::Channel
  include ApplicationCable::ClaimedLoop

  STREAM_PREFIX = "character_hunt_room_"

  # Seconds each phase lasts. The search uses the room's setting and ends early once enough players
  # have found the target; the host can skip the reveal.
  INTRO_DURATION  = 5  # "find this person"
  REVEAL_DURATION = 8
  GRACE_PERIOD    = 0.5 # after the search timer runs out, for taps still on their way
  EARLY_END_DELAY = 1   # so the last "found" shows before the reveal
  POLL_INTERVAL   = 0.25

  def subscribed
    @room   = Room.find_by(code: params[:room_code])
    @player = find_player
    return if subscription_rejected?

    track_player_subscribed(@player)
    stream_from room_stream

    sync
  end

  def unsubscribed
    track_player_unsubscribed(@player)
  end

  # Everything this screen may see right now, scene included: on connecting (a late or reloaded
  # phone joins the round, still frozen if it was) and whenever a screen asks again.
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
      Rails.logger.error("[CharacterHuntChannel] game loop crashed in room #{@room&.code}: #{e.message}\n#{e.backtrace.first(3).join("\n")}")
      broadcast({ action: "game_error" }) rescue nil
      @room&.update!(status: "finished") rescue nil
    end
  end

  # Moves on from the reveal.
  def skip(_data = nil)
    return unless host?

    service.skip!
  end

  def restart_game(_data = nil)
    return unless host?

    @room = Room.find_by(code: params[:room_code])
    GameServices::CharacterHunt.new(@room).setup_game!
    broadcast({ action: "game_restarted" })
  end

  # ── Player actions ────────────────────────────────────────────────────────

  # A tap on the scene: { x:, y: } (fractions of it) and an id the phone uses to match the answer.
  # The phone gets the result; everyone hears about finds and freezes.
  def tap(data)
    return unless @player

    svc    = GameServices::CharacterHunt.new(@room)
    result = svc.tap!(@player.id, data["x"], data["y"])
    transmit({ action: "tap_result", id: data["id"] }.merge(result))

    case result["result"]
    when "found"
      broadcast({ action: "found", player_id: @player.id.to_s, scores: svc.room.game_state["scores"] }
                  .merge(result.slice("place", "points", "time")))
    when "wrong"
      broadcast({ action: "frozen", player_id: @player.id.to_s, until: result["until"] })
    end
  end

  private

  # For each round: who to find → search → reveal. Then game over.
  def run_game(loop_id)
    svc    = GameServices::CharacterHunt.new(Room.find_by(code: params[:room_code]))
    svc.loop_id = loop_id
    rounds = svc.room.game_state["total_rounds"].to_i
    search = svc.room.game_state["round_time"].to_i

    (1..rounds).each do |round|
      phase(svc, loop_id, INTRO_DURATION) { svc.start_round!(round, INTRO_DURATION) } or return
      phase(svc, loop_id, search + GRACE_PERIOD, early: -> { svc.round_over? }) { svc.start_search! } or return
      phase(svc, loop_id, REVEAL_DURATION, early: -> { svc.skipped? }) { svc.end_round!(REVEAL_DURATION) } or return
    end

    return unless current_loop?(loop_id)

    svc.finish_game!
    send_state(svc)
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

  # The TV and the phones see the same state (a phone's freeze comes with its tap result).
  def send_state(svc)
    room = svc.room.reload
    broadcast({ action: "state", state: svc.public_state, nicknames: nicknames_map(room) })
  end

  def service
    GameServices::CharacterHunt.new(@room.reload)
  end

  def host?
    @player.nil?
  end

  def room_stream
    "#{STREAM_PREFIX}#{@room.code}"
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
