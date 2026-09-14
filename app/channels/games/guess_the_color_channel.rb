class Games::GuessTheColorChannel < ApplicationCable::Channel
  STREAM_PREFIX    = "guess_the_color_room_"
  SHOW_DURATION    = 5   # seconds the color is shown on host screen
  PICK_DURATION    = 10  # seconds players have to submit their pick
  REVEAL_DURATION  = 5   # seconds the reveal is shown before next round

  def subscribed
    @room   = Room.find_by(code: params[:room_code])
    @player = Player.find_by(id: params[:player_id]) if params[:player_id].present?

    @player&.update(connected: true)

    stream_from "#{STREAM_PREFIX}#{@room.code}"

    # Send current game state so reconnecting clients restore the right phase
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

  # Called by the host controller once the ActionCable connection is ready.
  def start_game_loop(data)
    return unless host?

    @room        = Room.find_by(code: params[:room_code])
    service      = GameServices::GuessTheColor.new(@room)
    total_rounds = @room.game_state["total_rounds"].to_i

    Thread.new do
      total_rounds.times do |i|
        round = i + 1

        # ── 1. Generate & show color ───────────────────────────────────────
        color = service.generate_color
        @room.set(
          "game_state.current_color" => color,
          "game_state.picks"         => {},
          "game_state.round"         => round,
          "game_state.status"        => "showing_color"
        )
        broadcast({
          action:       "show_color",
          color:        color,
          round:        round,
          total_rounds: total_rounds,
          duration:     SHOW_DURATION
        })
        sleep SHOW_DURATION

        # ── 2. Picking phase ───────────────────────────────────────────────
        @room.set("game_state.status" => "picking")
        broadcast({
          action:       "start_picking",
          duration:     PICK_DURATION,
          round:        round,
          total_rounds: total_rounds
        })
        sleep PICK_DURATION

        # ── 3. Score & reveal ──────────────────────────────────────────────
        @room.reload
        target       = @room.game_state["current_color"]
        picks        = @room.game_state["picks"] || {}
        scores       = @room.game_state["scores"] || {}
        round_scores = {}

        scores.each_key do |player_id|
          pick = picks[player_id]
          pts  = pick ? GameServices::GuessTheColor.calculate_score(target, pick) : 0
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
          target_color: target,
          picks:        picks,
          round_scores: round_scores,
          scores:       scores,
          nicknames:    nicknames_map,
          round:        round,
          total_rounds: total_rounds
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

  # Called by the host's Play Again button.
  def restart_game(data)
    return unless host?

    @room = Room.find_by(code: params[:room_code])
    GameServices::GuessTheColor.new(@room).setup_game!
    broadcast({ action: "game_restarted" })
  end

  # ── Player actions ────────────────────────────────────────────────────────

  # Called by the player when they lock in their RGB pick.
  def submit_color(data)
    return unless @player

    @room.reload
    return unless @room.game_state["status"] == "picking"

    # Ignore duplicate submissions
    picks = @room.game_state["picks"] || {}
    return if picks[@player.id.to_s]

    r = data["r"].to_i.clamp(0, 255)
    g = data["g"].to_i.clamp(0, 255)
    b = data["b"].to_i.clamp(0, 255)

    @room.set("game_state.picks.#{@player.id}" => { "r" => r, "g" => g, "b" => b })

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

  # { "player_id" => "nickname", ... } — built fresh each call so reconnects get correct names
  def nicknames_map
    @room.players.each_with_object({}) { |p, h| h[p.id.to_s] = p.nickname }
  end
end
