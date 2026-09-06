module GameServices
  class BattleCity < Base
    TANK_COLORS      = %w[yellow green white red].freeze
    PASSABLE_WALLS   = %w[trees].freeze
    MOVE_EVERY_TICKS = 4    # one cell every 4 × 60 ms ≈ 240 ms
    RESPAWN_TICKS    = 50   # 50 × 60 ms = 3 seconds

    # Bot behaviour
    BOT_FIRE_CHANCE   = 0.04   # probability of firing each tick
    BOT_TURN_CHANCE   = 0.04   # probability of random direction change each tick
    BOT_SPAWN_CELLS   = [
      { "x" => 1,  "y" => 1 },
      { "x" => 12, "y" => 1 },
      { "x" => 24, "y" => 1 }
    ].freeze

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
      bot_count   = (@room.game_state["bot_count"]   || 0).to_i.clamp(0, 3)
      players     = @players.first(max_players)

      walls       = build_walls(preset)
      tanks       = build_tanks(players, preset).merge(build_bot_tanks(bot_count))
      tank_spawns = build_tank_spawns(players, preset).merge(build_bot_spawns(bot_count))
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
          "map_rows"       => preset.rows,
          "kills_to_win"   => (@room.game_state["kills_to_win"] || 5).to_i,
          "bot_count"      => bot_count
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

      # ── 1. Player movement + firing ───────────────────────────────────────────
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

      # ── 2. Bot AI ─────────────────────────────────────────────────────────────
      tick_bots!(state).each { |id, t| changed_tanks[id] = t }

      # ── 3. Advance bullets + resolve collisions ────────────────────────────────
      walls_destroyed, kills, base_hit, bullets_changed = advance_bullets!(state)

      # ── 4. Apply kills + scoring ───────────────────────────────────────────────
      kills.each do |killed_id, killer_id|
        kill_tank!(state, killed_id)
        changed_tanks[killed_id] = state["tanks"][killed_id].dup
        # Only award score to human players (not bots)
        if state["scores"].key?(killer_id)
          state["scores"][killer_id] = state["scores"][killer_id].to_i + 1
        end
      end

      # ── 5. Respawns ────────────────────────────────────────────────────────────
      check_respawns!(state).each { |pid| changed_tanks[pid] = state["tanks"][pid].dup }

      # ── 6. Game over conditions ────────────────────────────────────────────────
      if base_hit
        state["status"]           = "game_over"
        state["game_over_reason"] = "base_destroyed"
      elsif human_tank_count(state) > 1 && alive_human_count(state) <= 1
        state["status"]           = "game_over"
        state["game_over_reason"] = "last_tank_standing"
      else
        kills_to_win = state["kills_to_win"].to_i
        if kills_to_win > 0
          # Only human player scores count toward the kill limit
          winner = state["scores"].find { |id, score| !bot_id?(id) && score.to_i >= kills_to_win }
          if winner
            state["status"]           = "game_over"
            state["game_over_reason"] = "kills_limit"
            state["winner_id"]        = winner[0]
          end
        end
      end

      # ── 7. Build delta ─────────────────────────────────────────────────────────
      delta = {}
      delta["tanks"]           = changed_tanks       unless changed_tanks.empty?
      delta["bullets"]         = state["bullets"]    if bullets_changed
      delta["walls_destroyed"] = walls_destroyed      unless walls_destroyed.empty?
      delta["scores"]          = state["scores"].dup  unless kills.empty?
      delta
    end

    private

    # ── Bot helpers ───────────────────────────────────────────────────────────────

    def bot_id?(id)
      id.to_s.start_with?("bot_")
    end

    def build_bot_tanks(count)
      count.times.each_with_object({}) do |i, h|
        spawn = BOT_SPAWN_CELLS[i]
        h["bot_#{i}"] = {
          "x"         => spawn["x"],
          "y"         => spawn["y"],
          "direction" => "down",
          "alive"     => true,
          "color"     => "silver",
          "nickname"  => "Bot #{i + 1}"
        }
      end
    end

    def build_bot_spawns(count)
      count.times.each_with_object({}) do |i, h|
        h["bot_#{i}"] = BOT_SPAWN_CELLS[i].dup
      end
    end

    # Simple bot AI: mostly drive downward toward the base, fire occasionally.
    def tick_bots!(state)
      changed = {}

      state["tanks"].each do |tank_id, tank|
        next unless bot_id?(tank_id) && tank["alive"]

        old_x   = tank["x"]
        old_y   = tank["y"]
        old_dir = tank["direction"]

        # Random direction change
        tank["direction"] = DIRECTIONS.keys.sample if rand < BOT_TURN_CHANCE

        # Movement — try current direction; turn randomly if blocked
        last_move = tank["last_move_tick"].to_i
        if (state["tick"] - last_move) >= MOVE_EVERY_TICKS
          unless move_tank!(state, tank, tank["direction"])
            tank["direction"] = DIRECTIONS.keys.sample
            move_tank!(state, tank, tank["direction"])
          end
          tank["last_move_tick"] = state["tick"]
        end

        # Fire
        fire!(state, tank_id, tank) if rand < BOT_FIRE_CHANCE && can_fire?(state, tank_id)

        if tank["x"] != old_x || tank["y"] != old_y || tank["direction"] != old_dir
          changed[tank_id] = tank.dup
        end
      end

      changed
    end

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

        if out_of_bounds?(state, nx, ny)
          to_remove << bullet["id"]
          next
        end

        wall_key = "#{nx},#{ny}"
        if (wall_type = state["walls"][wall_key])
          to_remove << bullet["id"]
          if wall_type == "brick"
            state["walls"].delete(wall_key)
            walls_destroyed << wall_key
          end
          next
        end

        base = state["base"]
        if base&.dig("alive") && nx == base["x"] && ny == base["y"]
          to_remove << bullet["id"]
          base["alive"] = false
          base_hit      = true
          next
        end

        hit = state["tanks"].find { |tid, t| t["alive"] && tid != bullet["owner_id"] && t["x"] == nx && t["y"] == ny }
        if hit
          tid, _ = hit
          to_remove << bullet["id"]
          kills[tid] = bullet["owner_id"]
          next
        end

        bullet["x"] = nx
        bullet["y"] = ny
      end

      state["bullets"].reject! { |b| to_remove.include?(b["id"]) }

      state["bullets"]
        .group_by { |b| "#{b['x']},#{b['y']}" }
        .each_value { |group| state["bullets"] -= group if group.size > 1 }

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

        next if state["tanks"].any? { |_, t| t["alive"] && t["x"] == spawn["x"] && t["y"] == spawn["y"] }

        tank.merge!(
          "x"              => spawn["x"],
          "y"              => spawn["y"],
          "direction"      => bot_id?(player_id) ? "down" : "up",
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

    def human_tank_count(state)
      state["tanks"].count { |id, _| !bot_id?(id) }
    end

    def alive_human_count(state)
      state["tanks"].count { |id, t| !bot_id?(id) && t["alive"] }
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
