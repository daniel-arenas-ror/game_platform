class Games::GuessTheColorChannel < ApplicationCable::Channel
  STREAM_PREFIX    = "guess_the_color_room_"
  REVEAL_DURATION  = 5   # seconds the reveal stays up once every colour is out
  REVEAL_STEP      = 0.5 # seconds between two colours coming out on the TV (furthest first)
  REVEAL_STEPS_MAX = 4   # …all of them within this many seconds, however many players

  def subscribed
    @room   = Room.find_by(code: params[:room_code])
    @player = find_player
    return if subscription_rejected?

    track_player_subscribed(@player)

    stream_from "#{STREAM_PREFIX}#{@room.code}"

    # Send current game state so reconnecting clients restore the right phase
    transmit({ action: "state_snapshot", state: @room.game_state })
  end

  def unsubscribed
    @stop_loop = true # the host left or reloaded: this loop ends (a reload starts a new one)
    return unless @player

    track_player_unsubscribed(@player)
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

    @stop_loop   = false
    @room        = Room.find_by(code: params[:room_code])
    service      = GameServices::GuessTheColor.new(@room)
    total_rounds = @room.game_state["total_rounds"].to_i
    pick_time    = GameServices::GuessTheColor.pick_time(@room.game_state["pick_time"])

    Thread.new do
      total_rounds.times do |i|
        break if @stop_loop
        round = i + 1

        # ── 1. Generate & show color (or, in real-world mode, name the thing) ─
        target = service.next_target!
        color  = target[:color]
        @room.atomic_set(
          "game_state.current_color" => color,
          "game_state.picks"         => {},
          "game_state.round"         => round,
          "game_state.status"        => "showing_color"
        )
        broadcast({
          action:       "show_color",
          color:        (color unless target[:prompt]),
          prompt:       target[:prompt],
          mode:         service.mode,
          round:        round,
          total_rounds: total_rounds,
          duration:     service.show_time
        })
        sleep service.show_time

        # ── 2. Picking phase ───────────────────────────────────────────────
        @room.atomic_set("game_state.status" => "picking")
        broadcast({
          action:       "start_picking",
          color:        (color if service.mode == "match"), # match mode: the colour stays on the TV
          prompt:       target[:prompt],
          duration:     pick_time,
          round:        round,
          total_rounds: total_rounds
        })
        sleep pick_time
        sleep 1.5   # grace period — lets in-flight client submissions arrive before we read picks

        # ── 3. Score & reveal ──────────────────────────────────────────────
        result = service.score_round!
        step   = [ REVEAL_STEP, REVEAL_STEPS_MAX.to_f / [ result[:scores].size, 1 ].max ].min
        broadcast({
          action:       "reveal",
          **result,
          prompt:       target[:prompt],
          step_ms:      (step * 1000).round,
          nicknames:    nicknames_map,
          round:        round,
          total_rounds: total_rounds
        })
        sleep REVEAL_DURATION + step * result[:scores].size
      end

      # ── 4. Game over ───────────────────────────────────────────────────
      unless @stop_loop
        @room.reload
        @room.update!(
          status:     "finished",
          game_state: @room.game_state.merge("status" => "game_over")
        )
        broadcast({
          action:    "game_over",
          scores:    @room.game_state["scores"],
          awards:    service.awards,
          nicknames: nicknames_map
        })
      end
    rescue => e
      Rails.logger.error("[GuessTheColorChannel] game loop crashed in room #{@room&.code}: #{e.message}\n#{e.backtrace.first(3).join("\n")}")
      broadcast({ action: "game_error" }) rescue nil
      @room&.update!(status: "finished") rescue nil
    end
  end

  # Called by the host's Play Again button.
  def restart_game(data)
    return unless host?

    @stop_loop = true
    @room = Room.find_by(code: params[:room_code])
    GameServices::GuessTheColor.new(@room).setup_game!
    broadcast({ action: "game_restarted" })
  end

  # ── Player actions ────────────────────────────────────────────────────────

  # Called automatically when the player's timer runs out.
  # No status guard — the 1.5s grace period means submissions can arrive
  # slightly after the server moves on. Duplicate check prevents double-scoring.
  def submit_color(data)
    return unless @player

    @room.reload

    # Ignore duplicate submissions and submissions after scoring is done
    picks = @room.game_state["picks"] || {}
    return if picks[@player.id.to_s]
    return if %w[revealing game_over].include?(@room.game_state["status"])

    r = data["r"].to_i.clamp(0, 255)
    g = data["g"].to_i.clamp(0, 255)
    b = data["b"].to_i.clamp(0, 255)

    @room.atomic_set("game_state.picks.#{@player.id}" => { "r" => r, "g" => g, "b" => b })

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
