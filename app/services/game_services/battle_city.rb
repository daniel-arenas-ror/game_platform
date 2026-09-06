module GameServices
  class BattleCity < Base
    TANK_COLORS     = %w[yellow green white red].freeze
    PASSABLE_WALLS  = %w[trees].freeze
    MOVE_EVERY_TICKS = 4   # one cell every 4 × 60 ms ≈ 240 ms (~4 cells/sec)

    DIRECTIONS = {
      "up"    => [ 0, -1],
      "down"  => [ 0,  1],
      "left"  => [-1,  0],
      "right" => [ 1,  0]
    }.freeze

    def initialize(room)
      @room    = room
      @players = room.players.to_a
    end

    def setup_game!
      preset_name = @room.game_state["map_preset"] || "classic"
      preset      = ::BattleCity::MapPreset.find_by(name: preset_name)
      max_players = (@room.game_state["max_players"] || 4).to_i
      players     = @players.first(max_players)

      walls  = build_walls(preset)
      tanks  = build_tanks(players, preset)
      scores = players.each_with_object({}) { |p, h| h[p.id.to_s] = 0 }

      @room.update!(
        status: "playing",
        game_state: @room.game_state.merge(
          "status"     => "playing",
          "tick"       => 0,
          "scores"     => scores,
          "base"       => { "x" => preset.base_x, "y" => preset.base_y, "alive" => true },
          "tanks"      => tanks,
          "bullets"        => [],
          "pending_inputs" => {},
          "walls"          => walls,
          "map_preset"     => preset_name,
          "map_cols"   => preset.cols,
          "map_rows"   => preset.rows
        )
      )

      broadcast_start
      true
    end

    # Advance one game tick.
    # state  — the in-memory game_state hash (mutated in place)
    # inputs — { player_id => { "direction" => "up"|…|nil, "firing" => true|false } }
    # Returns a delta hash (empty hash if nothing changed).
    def tick!(state, inputs)
      state["tick"] = state["tick"].to_i + 1
      changed_tanks = {}

      inputs.each do |player_id, input|
        direction = input["direction"]
        next if direction.nil? || direction.empty?

        tank = state["tanks"][player_id]
        next unless tank && tank["alive"]

        old_x         = tank["x"]
        old_y         = tank["y"]
        old_direction = tank["direction"]

        # Always turn to face the input direction immediately
        tank["direction"] = direction

        # Move one cell only when the cooldown has elapsed
        last_move = tank["last_move_tick"].to_i
        if (state["tick"] - last_move) >= MOVE_EVERY_TICKS
          if move_tank!(state, tank, direction)
            tank["last_move_tick"] = state["tick"]
          end
        end

        if tank["x"] != old_x || tank["y"] != old_y || tank["direction"] != old_direction
          changed_tanks[player_id] = tank.dup
        end
      end

      changed_tanks.empty? ? {} : { "tanks" => changed_tanks }
    end

    private

    def build_walls(preset)
      preset.cells.each_with_object({}) do |cell, h|
        h["#{cell['x']},#{cell['y']}"] = cell["type"]
      end
    end

    # Attempts to move tank one cell in direction.
    # Returns true if the tank actually moved, false if blocked.
    def move_tank!(state, tank, direction)
      delta = DIRECTIONS[direction]
      return false unless delta

      nx = tank["x"] + delta[0]
      ny = tank["y"] + delta[1]

      cols = state["map_cols"] || 26
      rows = state["map_rows"] || 26

      return false if nx < 0 || nx >= cols || ny < 0 || ny >= rows

      wall_type = state["walls"]["#{nx},#{ny}"]
      return false if wall_type && !PASSABLE_WALLS.include?(wall_type)

      occupied = state["tanks"].any? { |_, t| t["alive"] && t["x"] == nx && t["y"] == ny }
      return false if occupied

      tank["x"] = nx
      tank["y"] = ny
      true
    end

    def build_tanks(players, preset)
      players.each_with_index.each_with_object({}) do |(player, i), h|
        spawn = preset.tank_spawns[i]
        h[player.id.to_s] = {
          "x"         => spawn["x"],
          "y"         => spawn["y"],
          "direction" => "up",
          "alive"     => true,
          "color"     => TANK_COLORS[i],
          "nickname"  => player.nickname
        }
      end
    end
  end
end
