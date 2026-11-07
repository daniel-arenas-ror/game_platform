module GameServices
  class BattleCity < Base
    MAX_PLAYERS      = 8
    TANK_COLORS      = %w[yellow green white red blue purple orange pink].freeze
    # Where players start and come back, picked at random: the corners and the top, middle and
    # bottom of the map. A spot on a wall (each map is different) moves to the nearest free cell.
    SPAWN_SPOTS = [
      [ 2, 2 ], [ 23, 2 ], [ 2, 22 ], [ 23, 22 ],   # corners
      [ 12, 2 ], [ 2, 12 ], [ 23, 12 ], [ 12, 12 ], # top centre, left, right, centre
      [ 12, 22 ]                                    # bottom centre, where the base was
    ].freeze
    PASSABLE_WALLS   = %w[trees pine].freeze  # tanks drive through; bullets still stop
    BREAKABLE_WALLS  = %w[brick lights].freeze # a bullet breaks them (reindeer stay, like steel)
    MOVE_EVERY_TICKS = 4    # one cell every 4 × 60 ms ≈ 240 ms
    RESPAWN_TICKS    = 50   # 50 × 60 ms = 3 seconds
    SHIELD_TICKS     = 50   # a player who comes back can't be hit for 3 seconds, or until they fire

    # Bot behaviour
    BOT_FIRE_CHANCE   = 0.04   # probability of firing each tick
    BOT_TURN_CHANCE   = 0.04   # probability of random direction change each tick
    BOT_SPAWN_SPOTS   = [ [ 6, 1 ], [ 19, 1 ], [ 12, 5 ] ].freeze # between the players' top spots

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
      bot_count   = (@room.game_state["bot_count"]   || 0).to_i.clamp(0, 3)
      players     = @players.first(MAX_PLAYERS)

      walls       = build_walls(preset)
      spawns      = spawn_cells(walls, preset, bot_count)
      tanks       = build_tanks(players, spawns[:players].shuffle).merge(build_bot_tanks(bot_count, spawns))
      tank_spawns = tanks.select { |id, _| bot_id?(id) }.transform_values { |t| { "x" => t["x"], "y" => t["y"] } }
      scores      = players.each_with_object({}) { |p, h| h[p.id.to_s] = 0 }

      @room.update!(
        status: "playing",
        game_state: @room.game_state.merge(
          "status"         => "playing",
          "tick"           => 0,
          "scores"         => scores,
          "base"           => nil, # no base for now; a later mode can bring it back
          "tanks"          => tanks,
          "tank_spawns"    => tank_spawns,             # bots always come back where they started
          "spawn_points"   => spawns[:players],         # players come back at a random free one
          "bullets"        => [],
          "pending_inputs" => {},
          "walls"          => walls,
          "map_preset"     => preset_name,
          "map_theme"      => preset.theme,
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
      @shots        = []
      @bricks_by    = []

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

        if firing && can_fire?(state, player_id)
          fire!(state, player_id, tank)
          changed_tanks[player_id] = tank.dup if tank.delete("shield_until") # firing ends the shield
        end

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
        kill_tank!(state, killed_id, respawn: respawns?(state, killed_id))
        changed_tanks[killed_id] = state["tanks"][killed_id].dup
        # Only award score to human players (not bots)
        if state["scores"].key?(killer_id)
          state["scores"][killer_id] = state["scores"][killer_id].to_i + 1
        end
      end

      # ── 5. Respawns ────────────────────────────────────────────────────────────
      check_respawns!(state).each { |pid| changed_tanks[pid] = state["tanks"][pid].dup }
      expire_shields!(state).each { |pid| changed_tanks[pid] = state["tanks"][pid].dup }

      # ── 6. Game over conditions ────────────────────────────────────────────────
      if base_hit
        state["status"]           = "game_over"
        state["game_over_reason"] = "base_destroyed"
      elsif survival?(state)
        # No kill limit: destroyed players are out, the last one still driving wins.
        alive = state["tanks"].select { |id, t| !bot_id?(id) && t["alive"] }
        if alive.size <= 1
          state["status"]           = "game_over"
          state["game_over_reason"] = "last_tank_standing"
          state["winner_id"]        = alive.keys.first
        end
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
      delta["shots"]           = @shots               unless @shots.empty?   # who fired (sounds, recoil)
      delta["bricks_by"]       = @bricks_by           unless @bricks_by.empty?  # who broke a brick (sound)
      delta
    end

    private

    # ── Bot helpers ───────────────────────────────────────────────────────────────

    def bot_id?(id)
      id.to_s.start_with?("bot_")
    end

    def build_bot_tanks(count, spawns)
      count.times.each_with_object({}) do |i, h|
        x, y = spawns[:bots][i]
        h["bot_#{i}"] = {
          "x"         => x,
          "y"         => y,
          "direction" => "down",
          "alive"     => true,
          "color"     => "silver",
          "nickname"  => "Bot #{i + 1}"
        }
      end
    end

    # Simple bot AI: drive around, turn when blocked, fire occasionally.
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

    # The bullet starts in the cell in front of the barrel. When something is right there (a wall,
    # a tank, the base), it starts inside the tank instead, and this tick's bullet step hits it.
    def fire!(state, player_id, tank)
      d = DIRECTIONS[tank["direction"]]
      return unless d

      bx, by = tank["x"] + d[0], tank["y"] + d[1]
      bx, by = tank["x"], tank["y"] if blocked_for_bullet?(state, bx, by)

      state["bullets"] << {
        "id"        => "#{player_id}_#{state['tick']}",
        "owner_id"  => player_id,
        "x"         => bx,
        "y"         => by,
        "direction" => tank["direction"]
      }
      # A bullet can hit something in this same tick and never show up in a delta, so shots are
      # reported on their own.
      @shots&.push(player_id)
    end

    def blocked_for_bullet?(state, x, y)
      base = state["base"]
      out_of_bounds?(state, x, y) || state["walls"].key?("#{x},#{y}") ||
        (base&.dig("alive") && base["x"] == x && base["y"] == y) ||
        state["tanks"].any? { |_, t| t["alive"] && t["x"] == x && t["y"] == y }
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
          if BREAKABLE_WALLS.include?(wall_type)
            state["walls"].delete(wall_key)
            walls_destroyed << wall_key
            @bricks_by&.push(bullet["owner_id"])
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
          tid, tank = hit
          to_remove << bullet["id"]
          kills[tid] = bullet["owner_id"] unless tank["shield_until"] # a shield stops the bullet
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

    def kill_tank!(state, tank_id, respawn: true)
      tank                  = state["tanks"][tank_id]
      tank["alive"]         = false
      tank["respawn_tick"]  = respawn ? state["tick"] + RESPAWN_TICKS : nil
    end

    # No kill limit (0 kills to win) with 2+ players is a survival game: no respawns for players.
    # With a kill target, every tank comes back, so one kill never ends the game.
    def survival?(state)
      state["kills_to_win"].to_i.zero? && human_tank_count(state) > 1
    end

    def respawns?(state, tank_id)
      bot_id?(tank_id) || !survival?(state)
    end

    def check_respawns!(state)
      respawned = []

      state["tanks"].each do |player_id, tank|
        next if tank["alive"]
        next unless tank["respawn_tick"]
        next if state["tick"] < tank["respawn_tick"].to_i

        x, y = respawn_cell(state, player_id)
        next unless x

        tank.merge!(
          "x"              => x,
          "y"              => y,
          "direction"      => bot_id?(player_id) ? "down" : "up",
          "alive"          => true,
          "respawn_tick"   => nil,
          "last_move_tick" => 0
        )
        tank["shield_until"] = state["tick"] + SHIELD_TICKS unless bot_id?(player_id)
        respawned << player_id
      end

      respawned
    end

    # A player comes back at a random spawn point with no tank on it; a bot where it started.
    # Nil while every one is taken: it tries again next tick.
    def respawn_cell(state, tank_id)
      points = state["spawn_points"]
      points = [ state.dig("tank_spawns", tank_id)&.values_at("x", "y") ].compact if bot_id?(tank_id) || points.blank?
      points.reject { |x, y| state["tanks"].any? { |_, t| t["alive"] && t["x"] == x && t["y"] == y } }.sample
    end

    # Shields that ran out, so the TV stops flickering those tanks.
    def expire_shields!(state)
      state["tanks"].filter_map do |id, tank|
        next unless tank["shield_until"] && state["tick"] >= tank["shield_until"].to_i
        tank.delete("shield_until")
        id
      end
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

    def build_walls(preset)
      preset.cells_without_base.each_with_object({}) do |cell, h|
        h["#{cell['x']},#{cell['y']}"] = cell["type"]
      end
    end

    def build_tanks(players, cells)
      players.each_with_index.each_with_object({}) do |(player, i), h|
        x, y = cells[i]
        h[player.id.to_s] = {
          "x"         => x,
          "y"         => y,
          "direction" => "up",
          "alive"     => true,
          "color"     => TANK_COLORS[i],
          "nickname"  => player.nickname
        }
      end
    end

    # A different free cell for each player spot, then for each bot.
    def spawn_cells(walls, preset, bot_count)
      taken = []
      pick  = ->(spot) { free_cell_near(spot, walls, preset, taken).tap { |cell| taken << cell } }
      {
        players: SPAWN_SPOTS.map(&pick),
        bots:    BOT_SPAWN_SPOTS.first(bot_count).map(&pick)
      }
    end

    # The spot itself when it's free, else the closest cell with no wall (trees included, so nobody
    # starts hidden) and no other tank, inside the steel border.
    def free_cell_near(spot, walls, preset, taken)
      inside = ->(x, y) { x.between?(1, preset.cols - 2) && y.between?(1, preset.rows - 2) }
      seen   = { spot => true }
      queue  = [ spot ]
      until queue.empty?
        x, y = queue.shift
        return [ x, y ] if inside.(x, y) && !walls.key?("#{x},#{y}") && !taken.include?([ x, y ])

        DIRECTIONS.each_value do |dx, dy|
          cell = [ x + dx, y + dy ]
          next if seen[cell] || !inside.(*cell)
          seen[cell] = true
          queue << cell
        end
      end
      spot
    end
  end
end
