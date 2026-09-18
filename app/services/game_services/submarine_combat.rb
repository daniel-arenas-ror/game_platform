module GameServices
  class SubmarineCombat < Base
    # Ship sizes assigned per sub_count setting.
    # Each entry is an ordered array of ship lengths (largest first).
    SHIP_COMPOSITIONS = {
      2 => [3, 2],
      3 => [3, 2, 1],
      4 => [3, 2, 2, 1],
      5 => [3, 2, 2, 1, 1]
    }.freeze

    DEFAULT_SUB_COUNT  = 3
    DEFAULT_GRID_SIZE  = 8

    def initialize(room)
      @room    = room
      @players = room.players.to_a
    end

    # Called by RoomsController#start. Auto-places ships for every player,
    # sets phase to "placement" so players can shuffle/adjust before confirming.
    def setup_game!
      @room.update!(status: "playing")

      grid_size = (@room.game_state["grid_size"] || DEFAULT_GRID_SIZE).to_i
      sub_count = (@room.game_state["sub_count"] || DEFAULT_SUB_COUNT).to_i
      sub_count = SHIP_COMPOSITIONS.key?(sub_count) ? sub_count : DEFAULT_SUB_COUNT

      placements = {}
      scores     = {}

      @players.each do |player|
        placements[player.id.to_s] = {
          "ships"      => generate_placement(grid_size, sub_count),
          "confirmed"  => false,
          "eliminated" => false
        }
        scores[player.id.to_s] = 0
      end

      @room.set(
        "game_state.phase"        => "placement",
        "game_state.round"        => 0,
        "game_state.placements"   => placements,
        "game_state.round_picks"  => {},
        "game_state.shots"        => {},
        "game_state.scores"       => scores,
        "game_state.winner"       => nil
      )

      broadcast_start
    end

    # Generates a new random fleet for one player (used for shuffle).
    def generate_placement(grid_size, sub_count)
      sizes  = SHIP_COMPOSITIONS[sub_count] || SHIP_COMPOSITIONS[DEFAULT_SUB_COUNT]
      ships  = []
      occupied = []

      sizes.each do |size|
        cells    = place_ship(grid_size, size, occupied)
        occupied += cells
        ships << { "cells" => cells, "size" => size, "hits" => [] }
      end

      ships
    end

    # Scores one round: checks every player's grid against the picks hash
    # { player_id => [row, col] }. Returns a delta hash for broadcasting.
    def resolve_round!(round_picks)
      @room.reload
      placements = @room.game_state["placements"] || {}
      scores     = @room.game_state["scores"]     || {}
      shots      = @room.game_state["shots"]      || {}

      hits_this_round  = {}   # { firing_player_id => [[target_player_id, row, col], ...] }
      sunk_ships       = {}   # { target_player_id => [ship_index, ...] }
      newly_eliminated = []

      # Record each pick into global shot history
      round_picks.each do |shooter_id, coord|
        shots[shooter_id] ||= []
        shots[shooter_id] << coord
        hits_this_round[shooter_id] = []
      end

      # Check every pick against every opponent's grid
      round_picks.each do |shooter_id, (row, col)|
        placements.each do |target_id, placement|
          next if target_id == shooter_id
          next if placement["eliminated"]

          placement["ships"].each_with_index do |ship, ship_idx|
            next if ship["hits"].length == ship["size"]   # already sunk

            if ship["cells"].include?([row, col])
              ship["hits"] << [row, col]
              hits_this_round[shooter_id] << [target_id, row, col]
              scores[shooter_id] = scores[shooter_id].to_i + 1

              # Check if this hit sank the ship
              if ship["hits"].length == ship["size"]
                sunk_ships[target_id] ||= []
                sunk_ships[target_id] << ship_idx
              end
            end
          end
        end
      end

      # Eliminate players whose entire fleet is sunk
      placements.each do |player_id, placement|
        next if placement["eliminated"]

        all_sunk = placement["ships"].all? { |s| s["hits"].length == s["size"] }
        if all_sunk
          placement["eliminated"] = true
          newly_eliminated << player_id
        end
      end

      # Determine winner: last active player (or first to eliminate everyone)
      active = placements.reject { |_, p| p["eliminated"] }
      winner = active.keys.first if active.size == 1

      @room.set(
        "game_state.placements"  => placements,
        "game_state.scores"      => scores,
        "game_state.shots"       => shots,
        "game_state.round_picks" => {},
        "game_state.winner"      => winner
      )

      {
        hits:              hits_this_round,
        sunk_ships:        sunk_ships,
        eliminated:        newly_eliminated,
        scores:            scores,
        winner:            winner
      }
    end

    private

    # Attempts to place a ship of +size+ cells on a +grid_size+ × +grid_size+ grid
    # without overlapping +occupied+ cells (includes a 1-cell buffer zone).
    def place_ship(grid_size, size, occupied)
      200.times do
        horizontal = [true, false].sample
        if horizontal
          row  = rand(grid_size)
          col  = rand(grid_size - size + 1)
          cells = (0...size).map { |i| [row, col + i] }
        else
          row  = rand(grid_size - size + 1)
          col  = rand(grid_size)
          cells = (0...size).map { |i| [row + i, col] }
        end

        # Ensure no cell overlaps an already-occupied cell (exact overlap only)
        next if cells.any? { |c| occupied.include?(c) }

        return cells
      end

      raise "SubmarineCombat: could not place ship of size #{size} on #{grid_size}×#{grid_size} grid"
    end
  end
end
