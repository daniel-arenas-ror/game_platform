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

        # Fresh inputs from MongoDB (written by player_input on each player conn)
        @room.reload
        inputs = @room.game_state["pending_inputs"] || {}

        delta = service.tick!(state, inputs)

        # Broadcast only when something moved
        unless delta.empty?
          broadcast_to_room({ action: "state_delta", delta: delta })
        end

        # Persist tank positions so new subscribers get a fresh snapshot
        if state["tick"] % 10 == 0
          @room.set(
            "game_state.tanks" => state["tanks"],
            "game_state.tick"  => state["tick"]
          )
        end

        elapsed    = Process.clock_gettime(Process::CLOCK_MONOTONIC) - tick_start
        sleep_time = 0.060 - elapsed
        sleep(sleep_time) if sleep_time > 0
      end
    end
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
