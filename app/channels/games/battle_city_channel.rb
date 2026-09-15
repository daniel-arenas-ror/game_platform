class Games::BattleCityChannel < ApplicationCable::Channel
  STREAM_PREFIX = "battle_city_room_"

  def subscribed
    @room   = Room.find_by(code: params[:room_code])
    @player = Player.where(id: params[:player_id]).first if params[:player_id].present?

    @player&.update(connected: true)

    stream_from "#{STREAM_PREFIX}#{@room.code}"

    # Send the current full game state to the new subscriber only
    transmit({ action: "state_snapshot", state: @room.game_state })
  end

  def unsubscribed
    @running = false

    return unless @player

    @player.update(connected: false)
    ActionCable.server.broadcast("#{STREAM_PREFIX}#{@room.code}", {
      action: "player_presence",
      player_id: @player.id.to_s,
      connected: false
    })
  end

  # Called by the host once after the lobby Start button fires.
  def start_game_loop(data)
    return unless host?

    @room    = Room.find_by(code: params[:room_code])
    @running = true

    # ── Countdown ────────────────────────────────────────────────────────
    3.downto(1) do |n|
      broadcast_to_room({ action: "countdown", count: n })
      sleep 1
    end
    broadcast_to_room({ action: "countdown", count: 0 })   # "GO!"

    # Load live state into memory — the thread mutates this hash directly
    state = @room.reload.game_state.dup

    # ── Game loop (runs in its own thread) ────────────────────────────────
    Thread.new do
      service = GameServices::BattleCity.new(@room)

      loop do
        break unless @running


        tick_start = Process.clock_gettime(Process::CLOCK_MONOTONIC)

        @room.reload
        inputs = @room.game_state["pending_inputs"] || {}

        delta = service.tick!(state, inputs)

        # Persist full live state every 5 ticks so new subscribers get a fresh snapshot
        if state["tick"] % 5 == 0
          @room.set(
            "game_state.tanks"   => state["tanks"],
            "game_state.bullets" => state["bullets"],
            "game_state.walls"   => state["walls"],
            "game_state.scores"  => state["scores"],
            "game_state.base"    => state["base"],
            "game_state.tick"    => state["tick"]
          )
        end

        broadcast_to_room({ action: "state_delta", delta: delta }) unless delta.empty?

        # Game over — broadcast final result then stop the loop
        if state["status"] == "game_over"
          @running = false
          @room.update!(status: "finished", game_state: @room.game_state.merge("status" => "finished"))
          broadcast_to_room({
            action: "game_over",
            scores: state["scores"],
            reason: state["game_over_reason"]
          })
          break
        end

        elapsed    = Process.clock_gettime(Process::CLOCK_MONOTONIC) - tick_start
        sleep_time = 0.060 - elapsed
        sleep(sleep_time) if sleep_time > 0
      end
    rescue => e
      Rails.logger.error("[BattleCityChannel] game loop crashed in room #{@room&.code}: #{e.message}\n#{e.backtrace.first(3).join("\n")}")
      broadcast_to_room({ action: "game_error" }) rescue nil
      @room&.update!(status: "finished") rescue nil
    end
  end

  # Called by the host's "Play Again" button — resets state and reloads all clients.
  def restart_game
    return unless host?

    @running = false   # stop current loop if somehow still running
    @room    = Room.find_by(code: params[:room_code])

    GameServices::BattleCity.new(@room).setup_game!

    # Tell everyone to reload — they will re-subscribe and get a fresh state_snapshot
    broadcast_to_room({ action: "game_restarted" })
  end

  # Called by each player (or by the host keyboard in debug mode) to queue movement.
  def player_input(data)
    player_id = resolve_player_id(data)
    return unless player_id

    direction = data["direction"]   # "up" | "down" | "left" | "right" | nil
    firing    = data["firing"] == true

    @room.reload
    inputs = (@room.game_state["pending_inputs"] || {}).merge(
      player_id => { "direction" => direction, "firing" => firing }
    )
    @room.set("game_state.pending_inputs" => inputs)
  end

  private

  def host?
    @player.nil?
  end

  def broadcast_to_room(payload)
    ActionCable.server.broadcast("#{STREAM_PREFIX}#{@room.code}", payload)
  end

  # Players send their own id via session; the host can pass a player_id
  # directly for keyboard-testing during development.
  def resolve_player_id(data)
    return @player.id.to_s if @player
    return data["player_id"] if data["player_id"].present?
    nil
  end
end
