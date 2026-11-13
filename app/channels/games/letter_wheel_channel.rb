class Games::LetterWheelChannel < ApplicationCable::Channel
  include ApplicationCable::ClaimedLoop

  STREAM_PREFIX = "letter_wheel_room_"

  REVEAL_DURATION = 5
  GRACE_PERIOD    = 1.0 # after the time limit, for answers already on their way
  EARLY_END_DELAY = 0.5 # so the last answer shows before the reveal
  POLL_INTERVAL   = 0.25

  def subscribed
    @room   = Room.find_by(code: params[:room_code])
    @player = find_player
    return if subscription_rejected?

    track_player_subscribed(@player)
    stream_from room_stream

    service.join!(@player.id) if @player
    sync
  end

  def unsubscribed
    track_player_unsubscribed(@player)
  end

  # Everything this screen may see right now: on connecting and whenever a screen asks again.
  def sync(_data = nil)
    transmit({ action: "state", state: service.public_state, nicknames: nicknames_map })
  end

  # ── Host actions ──────────────────────────────────────────────────────────

  def start_game_loop(_data = nil)
    return unless host?

    loop_id = claim_loop
    return unless loop_id

    Thread.new do
      run_game(loop_id)
    rescue => e
      Rails.logger.error("[LetterWheelChannel] game loop crashed in room #{@room&.code}: #{e.message}\n#{e.backtrace.first(3).join("\n")}")
      broadcast({ action: "game_error" }) rescue nil
      @room&.update!(status: "finished") rescue nil
    end
  end

  def restart_game(_data = nil)
    return unless host?

    GameServices::LetterWheel.new(Room.find_by(code: params[:room_code])).setup_game!
    broadcast({ action: "game_restarted" })
  end

  # ── Player actions ────────────────────────────────────────────────────────

  # { text: "elephant" }. The phone hears right or wrong at once; every screen hears that it answered.
  def answer(data)
    return unless @player

    result = service.answer!(@player.id, data["text"])
    return unless result

    transmit({ action: "answer_result" }.merge(result))
    broadcast({ action: "answered", player_id: @player.id.to_s })
  end

  private

  # For each letter: the clue (until the time runs out or everyone answered) → the reveal. Then game
  # over. A loop that takes over from a dead one replays the current letter.
  def run_game(loop_id)
    svc   = GameServices::LetterWheel.new(Room.find_by(code: params[:room_code]))
    state = svc.room.game_state

    ([ state["round"].to_i, 1 ].max..state["words"].to_a.size).each do |round|
      phase(svc, loop_id, state["word_time"].to_i + GRACE_PERIOD, early: -> { svc.all_answered? }) { svc.start_round!(round) } or return
      phase(svc, loop_id, REVEAL_DURATION) { svc.score_round! } or return
    end

    return unless current_loop?(loop_id)

    svc.finish_game!
    send_state(svc)
  end

  # Starts a phase (the block), tells every screen, then waits for its timer, for `early` or for
  # the loop to be replaced. Returns false when the loop must stop.
  def phase(svc, loop_id, seconds, early: nil)
    return false unless current_loop?(loop_id) # Play Again may have replaced this loop meanwhile

    yield
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

  def send_state(svc)
    svc.room.reload
    broadcast({ action: "state", state: svc.public_state, nicknames: nicknames_map(svc.room) })
  end

  def service
    GameServices::LetterWheel.new(@room.reload)
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
