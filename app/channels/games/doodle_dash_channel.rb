class Games::DoodleDashChannel < ApplicationCable::Channel
  STREAM_PREFIX   = "doodle_dash_room_"
  START_DELAY     = 3    # seconds before the first turn
  REVEAL_DURATION = 6    # seconds the word and the points stay up after a turn
  GRACE_PERIOD    = 1    # extra time after a timer for in-flight messages
  POLL_INTERVAL   = 0.25 # how often a turn checks for a chosen word, all guessed, or the artist leaving
  HINTS_AT        = [ 0.5, 0.75 ].freeze # share of the drawing time when a letter is revealed
  ARTIST_CHECK    = 1.0  # seconds a "this player is drawing" check is trusted before asking again
  GUESS_COOLDOWN  = 0.4  # seconds between two guesses from the same phone

  def subscribed
    @room   = Room.find_by(code: params[:room_code])
    @player = find_player
    return if subscription_rejected?

    track_player_subscribed(@player)

    stream_from "#{STREAM_PREFIX}#{@room.code}"
    # The drawing and the wrong-guesses feed go to the TV only.
    stream_from host_stream if host?
    # The artist's word choices are pushed here by the game loop.
    stream_from player_stream(@player.id) if @player

    svc = service
    transmit({
      action:    "state_snapshot",
      state:     host? ? svc.host_state : svc.player_state(@player.id),
      nicknames: nicknames_map
    })
  end

  def unsubscribed
    return unless @player

    track_player_unsubscribed(@player)
    broadcast({ action: "player_presence", player_id: @player.id.to_s, connected: false })
  end

  # ── Host actions ──────────────────────────────────────────────────────────

  def start_game_loop(_data)
    return unless host?

    # Guard: only one loop per game, even if the host page reloads
    claimed = Room.collection.update_one(
      { "code" => params[:room_code], "status" => "playing", "game_state.loop_running" => { "$ne" => true } },
      { "$set" => { "game_state.loop_running" => true } }
    )
    return unless claimed.modified_count == 1

    # A restart replaces @loop_id, which stops a loop that is still sleeping
    loop_id = @loop_id = SecureRandom.hex(4)
    @room   = Room.find_by(code: params[:room_code])
    svc     = GameServices::DoodleDash.new(@room)

    Thread.new do
      sleep START_DELAY
      index = -1

      # total_turns is read every time: players who leave are taken out of the turns to come.
      while (index += 1) < svc.total_turns
        break if loop_id != @loop_id

        turn = svc.start_turn!(index)
        next unless turn # that artist left the room

        play_turn(svc, index, turn, loop_id)
        break if loop_id != @loop_id

        reveal = svc.end_turn!
        broadcast({ action: "turn_over", **reveal, turn: index + 1, total_turns: svc.total_turns, nicknames: nicknames_map })
        sleep REVEAL_DURATION # also after the last turn, so the last word stays up
      end

      if loop_id == @loop_id
        svc.finish_game!
        broadcast({ action: "game_over", scores: @room.game_state["scores"], nicknames: nicknames_map })
      end
    rescue => e
      Rails.logger.error("[DoodleDashChannel] game loop crashed in room #{@room&.code}: #{e.message}\n#{e.backtrace.first(3).join("\n")}")
      broadcast({ action: "game_error" }) rescue nil
      @room&.update!(status: "finished") rescue nil
    end
  end

  def restart_game(_data)
    return unless host?

    @loop_id = nil
    @room = Room.find_by(code: params[:room_code])
    GameServices::DoodleDash.new(@room).setup_game!
    broadcast({ action: "game_restarted" })
  end

  # ── Artist actions ────────────────────────────────────────────────────────

  def choose_word(data)
    return unless @player

    word = service.choose_word!(@player.id, data["index"])
    transmit({ action: "your_word", word: word }) if word
  end

  # A batch of points of the stroke being drawn. data: { points: [[x, y], …], color:, size:, start: }
  def draw(data)
    return unless drawing_artist?

    points = GameServices::DoodleDash.clean_points(data["points"])
    style  = GameServices::DoodleDash.clean_style(data["color"], data["size"])
    return unless points && style

    start = data["start"] || @stroke.nil?
    @stroke = style.merge("points" => []) if start
    @stroke["points"].concat(points) if @stroke["points"].length < 2000

    ActionCable.server.broadcast(host_stream, { action: "draw", start: start, points: points, **style.symbolize_keys })
  end

  # The stroke is finished: keep it, so a TV that reloads can redraw it.
  def stroke_end(_data)
    return unless @player && @stroke

    service.save_stroke!(@player.id, @stroke)
    @stroke = nil
  end

  def undo(_data)
    return unless @player && service.undo!(@player.id)

    @stroke = nil
    ActionCable.server.broadcast(host_stream, { action: "undo" })
  end

  def clear(_data)
    return unless @player && service.clear!(@player.id)

    @stroke = nil
    ActionCable.server.broadcast(host_stream, { action: "clear" })
  end

  # ── Guesser actions ───────────────────────────────────────────────────────

  def guess(data)
    return unless @player

    now = monotonic_now
    return if @last_guess_at && now - @last_guess_at < GUESS_COOLDOWN

    @last_guess_at = now
    svc    = service
    result = svc.guess!(@player.id, data["text"])
    return transmit({ action: "guess_rejected" }) unless result[:ok]

    transmit({ action: "guess_result", **result.except(:ok, :text) })
    pid = @player.id.to_s

    case result[:result]
    when "correct"
      broadcast({ action: "guessed", player_id: pid, points: result[:points], scores: @room.game_state["scores"] })
    when "close"
      ActionCable.server.broadcast(host_stream, { action: "feed", player_id: pid, kind: "close" })
    when "wrong"
      if @room.game_state["show_guesses"]
        ActionCable.server.broadcast(host_stream, { action: "feed", player_id: pid, kind: "wrong", text: result[:text] })
      end
    end
  end

  private

  # Word choice, then drawing. Returns early when the artist leaves or the loop is replaced.
  def play_turn(svc, index, turn, loop_id)
    artist_id = turn[:artist_id]
    broadcast({ action: "choosing", turn: index + 1, total_turns: svc.total_turns, artist_id: artist_id,
                duration: GameServices::DoodleDash::CHOOSE_TIME, nicknames: nicknames_map })
    ActionCable.server.broadcast(player_stream(artist_id),
                                 { action: "choose_word", choices: turn[:choices], duration: GameServices::DoodleDash::CHOOSE_TIME })

    wait_for(GameServices::DoodleDash::CHOOSE_TIME + GRACE_PERIOD, loop_id) do
      state = Room.where(_id: @room.id).only(:game_state).first.game_state
      state["status"] != "choosing" || state["artist_left"]
    end
    return if loop_id != @loop_id || svc.artist_left?

    svc.choose_word!(nil) # no-op if the artist already picked
    @room.reload
    return unless @room.game_state["status"] == "drawing"

    state     = @room.game_state
    draw_time = state["draw_time"].to_i
    broadcast({ action: "drawing", artist_id: artist_id, pattern: state["pattern"],
                duration: draw_time, turn_ends_at: state["turn_ends_at"] })
    ActionCable.server.broadcast(player_stream(artist_id), { action: "your_word", word: state["word"] })

    started = monotonic_now
    hints   = HINTS_AT.map { |share| started + draw_time * share }

    wait_for(draw_time + GRACE_PERIOD, loop_id) do
      if hints.any? && monotonic_now >= hints.first
        hints.shift
        pattern = svc.reveal_hint!
        broadcast({ action: "hint", pattern: pattern }) if pattern
      end
      svc.all_guessed? || svc.artist_left?
    end
  end

  # Sleeps until the block returns true, the time runs out, or the loop is replaced.
  def wait_for(seconds, loop_id)
    deadline = monotonic_now + seconds

    while monotonic_now < deadline
      return if loop_id != @loop_id
      return if yield

      sleep POLL_INTERVAL
    end
  end

  # Strokes arrive many times a second, so the "is this the artist?" answer is cached briefly.
  def drawing_artist?
    return false unless @player

    now = monotonic_now
    if @artist_checked_at.nil? || now - @artist_checked_at > ARTIST_CHECK
      @artist_checked_at = now
      @is_artist = service.drawing_artist?(@player.id)
    end
    @is_artist
  end

  def monotonic_now
    Process.clock_gettime(Process::CLOCK_MONOTONIC)
  end

  def service
    GameServices::DoodleDash.new(@room)
  end

  def host?
    @player.nil?
  end

  def host_stream
    "#{STREAM_PREFIX}#{@room.code}_host"
  end

  def player_stream(player_id)
    "#{STREAM_PREFIX}#{@room.code}_player_#{player_id}"
  end

  def broadcast(payload)
    ActionCable.server.broadcast("#{STREAM_PREFIX}#{@room.code}", payload)
  end

  def nicknames_map
    @room.players.each_with_object({}) { |p, h| h[p.id.to_s] = p.nickname }
  end
end
