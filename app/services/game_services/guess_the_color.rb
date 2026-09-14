module GameServices
  class GuessTheColor < Base
    MAX_DISTANCE = Math.sqrt(255**2 * 3)  # ≈ 441.67

    # Easy mode: 12 vivid hues spaced 30° apart, full saturation, mid lightness
    EASY_HUES = (0..330).step(30).to_a.freeze

    def initialize(room)
      @room    = room
      @players = room.players.to_a
    end

    def setup_game!
      total_rounds = (@room.game_state["total_rounds"] || 5).to_i
      difficulty   = @room.game_state["difficulty"] || "easy"
      scores       = @players.each_with_object({}) { |p, h| h[p.id.to_s] = 0 }

      @room.update!(
        status: "playing",
        game_state: @room.game_state.merge(
          "status"        => "waiting",
          "round"         => 0,
          "total_rounds"  => total_rounds,
          "difficulty"    => difficulty,
          "scores"        => scores,
          "current_color" => nil,
          "picks"         => {},
          "round_scores"  => {}
        )
      )

      broadcast_start
      true
    end

    # Returns a random color hash {r, g, b} based on difficulty.
    def generate_color
      difficulty = @room.game_state["difficulty"] || "easy"
      if difficulty == "easy"
        hsl_to_rgb(EASY_HUES.sample, 1.0, 0.5)
      else
        { "r" => rand(256), "g" => rand(256), "b" => rand(256) }
      end
    end

    # Returns 0–1000 points based on RGB distance between target and pick.
    def self.calculate_score(target, pick)
      return 0 unless target && pick
      dr = (target["r"].to_i - pick["r"].to_i)
      dg = (target["g"].to_i - pick["g"].to_i)
      db = (target["b"].to_i - pick["b"].to_i)
      distance = Math.sqrt(dr**2 + dg**2 + db**2)
      (1000 * (1.0 - distance / MAX_DISTANCE)).round.clamp(0, 1000)
    end

    private

    def hsl_to_rgb(h, s, l)
      c  = (1 - (2 * l - 1).abs) * s
      x  = c * (1 - ((h / 60.0) % 2 - 1).abs)
      m  = l - c / 2.0

      r1, g1, b1 = case h
                   when 0...60   then [c, x, 0]
                   when 60...120 then [x, c, 0]
                   when 120...180 then [0, c, x]
                   when 180...240 then [0, x, c]
                   when 240...300 then [x, 0, c]
                   else               [c, 0, x]
                   end

      {
        "r" => ((r1 + m) * 255).round,
        "g" => ((g1 + m) * 255).round,
        "b" => ((b1 + m) * 255).round
      }
    end
  end
end
