class Games::CountBirdsChannel < ApplicationCable::Channel
  STREAM_PREFIX      = "count_birds_room_"
  MIN_COUNT_DURATION = 5    # seconds on round 1
  MAX_COUNT_DURATION = 15   # cap — reached gradually as rounds progress
  GRACE_PERIOD       = 1.5  # extra wait before reading picks (handles client timer drift)
  REVEAL_DURATION    = 4    # seconds the reveal is shown before next round

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

    @room        = Room.find_by(code: params[:room_code])
    total_rounds = @room.game_state["total_rounds"].to_i

    Thread.new do
      total_rounds.times do |i|
        round = i + 1

        # ── 1. Generate round config ───────────────────────────────────────
        density          = @room.game_state["density"] || "normal"
        bird_count       = GameServices::CountBirds.bird_count_for(round, density: density)
        difficulty       = GameServices::CountBirds.difficulty_for(round)
        distractor_count = GameServices::CountBirds.distractor_count_for(round)
        count_duration   = GameServices::CountBirds.count_duration_for(round, total_rounds)

        @room.set(
          "game_state.round"       => round,
          "game_state.bird_count"  => bird_count,
          "game_state.picks"       => {},
          "game_state.status"      => "counting"
        )

        broadcast({
          action:           "start_round",
          round:            round,
          total_rounds:     total_rounds,
          bird_count:       bird_count,
          difficulty:       difficulty,
          distractor_count: distractor_count,
          duration:         count_duration
        })

        # ── 2. Wait for players to count ───────────────────────────────────
        sleep count_duration
        sleep GRACE_PERIOD   # let in-flight submissions arrive

        # ── 3. Score picks ─────────────────────────────────────────────────
        @room.reload
        picks        = @room.game_state["picks"] || {}
        scores       = @room.game_state["scores"] || {}
        round_scores = {}

        scores.each_key do |player_id|
          guess = picks[player_id]
          pts   = GameServices::CountBirds.calculate_score(bird_count, guess)
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
          bird_count:   bird_count,
          picks:        picks,
          round_scores: round_scores,
          scores:       scores,
          nicknames:    nicknames_map
        })

        sleep REVEAL_DURATION
      end

      # ── 4. Game over ───────────────────────────────────────────────────
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
  end

  def restart_game(data)
    return unless host?

    @room = Room.find_by(code: params[:room_code])
    GameServices::CountBirds.new(@room).setup_game!
    broadcast({ action: "game_restarted" })
  end

  # ── Player actions ────────────────────────────────────────────────────────

  # Auto-called when the player's timer runs out with their current +/- count.
  def submit_count(data)
    return unless @player

    @room.reload

    # Reject submissions after scoring is done
    return if %w[revealing game_over].include?(@room.game_state["status"])

    # Ignore duplicate submissions
    picks = @room.game_state["picks"] || {}
    return if picks[@player.id.to_s]

    count = data["count"].to_i.clamp(0, 999)

    @room.set("game_state.picks.#{@player.id}" => count)

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
