module GameServices
  class BattleCity < Base
    TANK_COLORS      = %w[yellow green white red].freeze
    PASSABLE_WALLS   = %w[trees].freeze
    MOVE_EVERY_TICKS = 4    # one cell every 4 × 60 ms ≈ 240 ms
    RESPAWN_TICKS    = 50   # 50 × 60 ms = 3 seconds

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

      walls       = build_walls(preset)
      tanks       = build_tanks(players, preset)
      tank_spawns = build_tank_spawns(players, preset)
      scores      = players.each_with_object({}) { |p, h| h[p.id.to_s] = 0 }

      @room.update!(
        status: "playing",
        game_state: @room.game_state.merge(
          "status"         => "playing",
          "tick"           => 0,
          "scores"         => scores,
          "base"           => { "x" => preset.base_x, "y" => preset.base_y, "alive" => true },
          "tanks"          => tanks,
          "tank_spawns"    => tank_spawns,
          "bullets"        => [],
          "pending_inputs" => {},
          "walls"          => walls,
          "map_preset"     => preset_name,
          "map_cols"       => preset.cols,
          "map_rows"       => preset.rows
        )
      )

      broadcast_start
      true
    end

    # Advance one game tick.
    # state  — in-memory game_state hash (mutated in place)
    # inputs — { player_id => { "direction" => String|nil, "firing" => Boolean } }
    # Returns a delta hash (empty when nothing changed).
    def tick!(state, inputs)
      state["tick"] = state["tick"].to_i + 1
      changed_tanks = {}

      # ── 1. Movement + firing ───────────────────────────────────────────────
      inputs.each do |player_id, input|
        tank = state["tanks"][player_id]
        next unless tank && tank["alive"]

        direction = input["direction"]
        firing    = input["firing"]

        old_x         = tank["x"]
        old_y         = tank["y"]
        old_direction = tank["direction"]

        if direction && !direction.empty?
          tank["direction"] = direction
          last_move = tank["last_move_tick"].to_i
          if (state["tick"] - last_move) >= MOVE_EVERY_TICKS
            tank["last_move_tick"] = state["tick"] if move_tank!(state, tank, direction)
          end
        end

        fire!(state, player_id, tank) if firing && can_fire?(state, player_id)

        if tank["x"] != old_x || tank["y"] != old_y || tank["direction"] != old_direction
          changed_tanks[player_id] = tank.dup
        end
      end

      # ── 2. Advance bullets + resolve collisions ────────────────────────────
      walls_destroyed, kills, base_hit, bullets_changed = advance_bullets!(state)

      # ── 3. Apply kills + scoring ───────────────────────────────────────────
      kills.each do |killed_id, killer_id|
        kill_tank!(state, killed_id)
        changed_tanks[killed_id]        = state["tanks"][killed_id].dup
        state["scores"][killer_id]      = state["scores"][killer_id].to_i + 1
      end

      # ── 4. Respawns ────────────────────────────────────────────────────────
      check_respawns!(state).each { |pid| changed_tanks[pid] = state["tanks"][pid].dup }

      # ── 5. Game over conditions ────────────────────────────────────────────
      if base_hit
        state["status"]            = "game_over"
        state["game_over_reason"]  = "base_destroyed"
      elsif state["tanks"].size > 1 && alive_count(state) <= 1
        state["status"]            = "game_over"
        state["game_over_reason"]  = "last_tank_standing"
      end

      # ── 6. Build delta ─────────────────────────────────────────────────────
      delta = {}
      delta["tanks"]           = changed_tanks       unless changed_tanks.empty?
      delta["bullets"]         = state["bullets"]    if bullets_changed
      delta["walls_destroyed"] = walls_destroyed      unless walls_destroyed.empty?
      delta["scores"]          = state["scores"].dup  unless kills.empty?
      delta
    end

    private

    # ── Movement ──────────────────────────────────────────────────────────────

    def move_tank!(state, tank, direction)
      d  = DIRECTIONS[direction]
      return false unless d

      nx = tank["x"] + d[0]
      ny = tank["y"] + d[1]

      return false if out_of_bounds?(state, nx, ny)

      wall_type = state["walls"]["#{nx},#{ny}"]
      return false if wall_type && !PASSABLE_WALLS.include?(wall_type)

      return false if state["tanks"].any? { |_, t| t["alive"] && t["x"] == nx && t["y"] == ny }

      tank["x"] = nx
      tank["y"] = ny
      true
    end

    # ── Firing ────────────────────────────────────────────────────────────────

    def can_fire?(state, player_id)
      state["bullets"].none? { |b| b["owner_id"] == player_id }
    end

    def fire!(state, player_id, tank)
      d  = DIRECTIONS[tank["direction"]]
      bx = tank["x"] + d[0]
      by = tank["y"] + d[1]

      # Abort if the muzzle cell is out of bounds or blocked by a solid wall
      return if out_of_bounds?(state, bx, by)
      wall_type = state["walls"]["#{bx},#{by}"]
      return if wall_type && !PASSABLE_WALLS.include?(wall_type)

      state["bullets"] << {
        "id"        => "#{player_id}_#{state['tick']}",
        "owner_id"  => player_id,
        "x"         => bx,
        "y"         => by,
        "direction" => tank["direction"]
      }
    end

    # ── Bullet advancement ────────────────────────────────────────────────────

    def advance_bullets!(state)
      to_remove       = []
      walls_destroyed = []
      kills           = {}
      base_hit        = false

      state["bullets"].each do |bullet|
        d  = DIRECTIONS[bullet["direction"]]
        nx = bullet["x"] + d[0]
        ny = bullet["y"] + d[1]

        # Out of bounds
        if out_of_bounds?(state, nx, ny)
          to_remove << bullet["id"]
          next
        end

        # Wall hit
        wall_key = "#{nx},#{ny}"
        if (wall_type = state["walls"][wall_key])
          to_remove << bullet["id"]
          if wall_type == "brick"
            state["walls"].delete(wall_key)
            walls_destroyed << wall_key
          end
          next
        end

        # Base hit
        base = state["base"]
        if base&.dig("alive") && nx == base["x"] && ny == base["y"]
          to_remove << bullet["id"]
          base["alive"] = false
          base_hit      = true
          next
        end

        # Tank hit — bullets cannot hit their owner
        hit = state["tanks"].find { |tid, t| t["alive"] && tid != bullet["owner_id"] && t["x"] == nx && t["y"] == ny }
        if hit
          tid, _ = hit
          to_remove << bullet["id"]
          kills[tid] = bullet["owner_id"]  # killed_id => killer_id
          next
        end

        # No collision — move the bullet forward
        bullet["x"] = nx
        bullet["y"] = ny
      end

      state["bullets"].reject! { |b| to_remove.include?(b["id"]) }

      # Bullet-on-bullet: if two bullets share a cell after advancing, cancel both
      state["bullets"]
        .group_by { |b| "#{b['x']},#{b['y']}" }
        .each_value { |group| state["bullets"] -= group if group.size > 1 }

      # bullets_changed when: bullets exist (they moved), or any were destroyed / created this tick
      bullets_changed = !state["bullets"].empty? || !to_remove.empty?

      [walls_destroyed, kills, base_hit, bullets_changed]
    end

    # ── Kill / Respawn ────────────────────────────────────────────────────────

    def kill_tank!(state, tank_id)
      tank                  = state["tanks"][tank_id]
      tank["alive"]         = false
      tank["respawn_tick"]  = state["tick"] + RESPAWN_TICKS
    end

    def check_respawns!(state)
      respawned = []

      state["tanks"].each do |player_id, tank|
        next if tank["alive"]
        next unless tank["respawn_tick"]
        next if state["tick"] < tank["respawn_tick"].to_i

        spawn = state.dig("tank_spawns", player_id)
        next unless spawn

        # Delay respawn if the spawn cell is occupied
        next if state["tanks"].any? { |_, t| t["alive"] && t["x"] == spawn["x"] && t["y"] == spawn["y"] }

        tank.merge!(
          "x"              => spawn["x"],
          "y"              => spawn["y"],
          "direction"      => "up",
          "alive"          => true,
          "respawn_tick"   => nil,
          "last_move_tick" => 0
        )
        respawned << player_id
      end

      respawned
    end

    # ── Helpers ───────────────────────────────────────────────────────────────

    def out_of_bounds?(state, x, y)
      x < 0 || x >= (state["map_cols"] || 26) || y < 0 || y >= (state["map_rows"] || 26)
    end

    def alive_count(state)
      state["tanks"].count { |_, t| t["alive"] }
    end

    def build_walls(preset)
      preset.cells.each_with_object({}) do |cell, h|
        h["#{cell['x']},#{cell['y']}"] = cell["type"]
      end
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

    def build_tank_spawns(players, preset)
      players.each_with_index.each_with_object({}) do |(player, i), h|
        h[player.id.to_s] = {
          "x" => preset.tank_spawns[i]["x"],
          "y" => preset.tank_spawns[i]["y"]
        }
      end
    end
  end
end
