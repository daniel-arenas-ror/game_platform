module GameServices
  class GuessTheColor < Base
    # Scoring compares colours the way eyes do (OKLab), not by RGB numbers. A pick this far away in
    # OKLab keeps ~37% of the points; closer picks score much higher (0.03 ≈ 97%, a "perfect").
    MATCH_SPREAD  = 0.17
    PERFECT_MATCH = 97 # % shown as "Perfect!" on the phones and the TV

    # Easy mode: 12 vivid hues spaced 30° apart, full saturation, mid lightness
    EASY_HUES = (0..330).step(30).to_a.freeze

    # Seconds players get to mix the color, picked on the settings screen.
    PICK_TIMES        = [ 5, 10, 15 ].freeze
    DEFAULT_PICK_TIME = 10

    def self.pick_time(value)
      PICK_TIMES.include?(value.to_i) ? value.to_i : DEFAULT_PICK_TIME
    end

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
          "pick_time"     => self.class.pick_time(@room.game_state["pick_time"]),
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

    # 0–1000 points: 1000 × how alike the two colours look (a bell curve on their OKLab distance).
    def self.calculate_score(target, pick)
      return 0 unless target && pick

      distance = Math.sqrt(oklab(target).zip(oklab(pick)).sum { |a, b| (a - b)**2 })
      (1000 * Math.exp(-(distance / MATCH_SPREAD)**2)).round.clamp(0, 1000)
    end

    # "94" for 940 points: the % match the phones and the TV show.
    def self.match_percent(points)
      (points / 10.0).round
    end

    # sRGB {r, g, b} (0–255) → OKLab [L, a, b] (Björn Ottosson's OKLab).
    def self.oklab(color)
      r, g, b = %w[r g b].map do |key|
        c = color[key].to_f.clamp(0, 255) / 255
        c <= 0.04045 ? c / 12.92 : ((c + 0.055) / 1.055)**2.4
      end
      l = Math.cbrt(0.4122214708 * r + 0.5363325363 * g + 0.0514459929 * b)
      m = Math.cbrt(0.2119034982 * r + 0.6806995451 * g + 0.1073969566 * b)
      s = Math.cbrt(0.0883024619 * r + 0.2817188376 * g + 0.6299787005 * b)
      [ 0.2104542553 * l + 0.7936177850 * m - 0.0040720468 * s,
        1.9779984951 * l - 2.4285922050 * m + 0.4505937099 * s,
        0.0259040371 * l + 0.7827717662 * m - 0.8086757660 * s ]
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
