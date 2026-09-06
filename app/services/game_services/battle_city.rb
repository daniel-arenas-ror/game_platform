module GameServices
  class BattleCity < Base
    TANK_COLORS = %w[yellow green white red].freeze

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
          "bullets"    => [],
          "walls"      => walls,
          "map_preset" => preset_name,
          "map_cols"   => preset.cols,
          "map_rows"   => preset.rows
        )
      )

      broadcast_start
      true
    end

    private

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
  end
end
