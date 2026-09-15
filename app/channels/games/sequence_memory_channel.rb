class Games::SequenceMemoryChannel < ApplicationCable::Channel
  STREAM_PREFIX    = "sequence_memory_room_"
  GRACE_PERIOD     = 1.5  # extra wait after input timer expires (handles client drift)
  REVEAL_DURATION  = 4    # seconds the reveal is shown before the next round

  def subscribed
    @room   = Room.find_by(code: params[:room_code])
    @player = Player.find_by(id: params[:player_id]) if params[:player_id].present?

    @player&.update(connected: true)

    stream_from "#{STREAM_PREFIX}#{@room.code}"

    transmit({ action: "state_snapshot", state: @room.game_state })
  end

  def unsubscribed
    return unless @player

    @player.update(connected: false)
    broadcast({
      action:    "player_presence",
      player_id: @player.id.to_s,
      connected: false
    })
  end

  # ── Host actions ──────────────────────────────────────────────────────────

  def start_game_loop(data)
    return unless host?

    @stop_loop   = false
    @room        = Room.find_by(code: params[:room_code])
    total_rounds = @room.game_state["total_rounds"].to_i
    svc          = GameServices::SequenceMemory.new(@room)

    Thread.new do
      total_rounds.times do |i|
        break if @stop_loop
        round = i + 1

        # ── 1. Extend the sequence by one cell ────────────────────────────
        sequence = svc.next_sequence!

        @room.set(
          "game_state.round"       => round,
          "game_state.submissions" => {},
          "game_state.status"      => "watching"
        )

        playback_duration = GameServices::SequenceMemory.playback_duration_for(sequence.length)
        input_duration    = GameServices::SequenceMemory.input_duration_for(round)

        # ── 2. Tell everyone to show the sequence ─────────────────────────
        broadcast({
          action:            "show_sequence",
          round:             round,
          total_rounds:      total_rounds,
          sequence:          sequence,
          flash_duration:    GameServices::SequenceMemory::FLASH_DURATION,
          flash_gap:         GameServices::SequenceMemory::FLASH_GAP,
          playback_duration: playback_duration
        })

        # ── 3. Wait for the host to finish animating ───────────────────────
        sleep playback_duration

        # ── 4. Open input window for players ──────────────────────────────
        @room.set("game_state.status" => "input")

        broadcast({
          action:         "player_turn",
          round:          round,
          total_rounds:   total_rounds,
          sequence_length: sequence.length,
          input_duration: input_duration
        })

        sleep input_duration
        sleep GRACE_PERIOD  # let in-flight submissions land

        # ── 5. Score all submissions ───────────────────────────────────────
        @room.reload
        submissions  = @room.game_state["submissions"] || {}
        scores       = @room.game_state["scores"]      || {}
        round_scores = {}

        scores.each_key do |player_id|
          sub = submissions[player_id]   # Array of cell indices, or nil
          pts = GameServices::SequenceMemory.calculate_score(sequence, sub)
          round_scores[player_id] = pts
          scores[player_id]       = scores[player_id].to_i + pts
        end

        @room.set(
          "game_state.scores"       => scores,
          "game_state.round_scores" => round_scores,
          "game_state.status"       => "revealing"
        )

        broadcast({
          action:       "reveal",
          round:        round,
          total_rounds: total_rounds,
          sequence:     sequence,
          submissions:  submissions,
          round_scores: round_scores,
          scores:       scores,
          nicknames:    nicknames_map
        })

        sleep REVEAL_DURATION
      end

      # ── 6. Game over ──────────────────────────────────────────────────────
      unless @stop_loop
        @room.reload
        @room.update!(
          status:     "finished",
          game_state: @room.game_state.merge("status" => "game_over")
        )
        broadcast({
          action:    "game_over",
          scores:    @room.game_state["scores"],
          nicknames: nicknames_map
        })
      end
    rescue => e
      Rails.logger.error("[SequenceMemoryChannel] game loop crashed in room #{@room&.code}: #{e.message}\n#{e.backtrace.first(3).join("\n")}")
      broadcast({ action: "game_error" }) rescue nil
      @room&.update!(status: "finished") rescue nil
    end
  end

  def restart_game(data)
    return unless host?

    @stop_loop = true
    @room = Room.find_by(code: params[:room_code])
    GameServices::SequenceMemory.new(@room).setup_game!
    broadcast({ action: "game_restarted" })
  end

  # ── Player actions ────────────────────────────────────────────────────────

  # Called when the player's timer runs out or they complete the sequence early.
  # data["sequence"] is an Array of cell indices in tap order.
  def submit_sequence(data)
    return unless @player

    @room.reload

    # Reject if scoring window has closed
    return if %w[revealing game_over watching].include?(@room.game_state["status"])

    # Ignore duplicate submissions
    submissions = @room.game_state["submissions"] || {}
    return if submissions[@player.id.to_s]

    raw = data["sequence"]
    return unless raw.is_a?(Array)

    # Clamp each index to a valid cell number; cap array length for safety
    grid_size   = (@room.game_state["grid_size"] || 4).to_i
    max_cells   = grid_size * grid_size
    seq_length  = (@room.game_state["sequence"] || []).length
    submission  = raw.map { |c| c.to_i.clamp(0, max_cells - 1) }.first(seq_length)

    @room.set("game_state.submissions.#{@player.id}" => submission)

    broadcast({
      action:    "player_submitted",
      player_id: @player.id.to_s,
      nickname:  @player.nickname
    })
  end

  private

  def host?
    @player.nil?
  end

  def broadcast(payload)
    ActionCable.server.broadcast("#{STREAM_PREFIX}#{@room.code}", payload)
  end

  def nicknames_map
    @room.players.each_with_object({}) { |p, h| h[p.id.to_s] = p.nickname }
  end
end
