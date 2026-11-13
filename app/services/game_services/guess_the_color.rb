module GameServices
  class GuessTheColor < Base
    # Scoring compares colours the way eyes do (OKLab), not by RGB numbers. A pick this far away in
    # OKLab keeps ~37% of the points; closer picks score much higher (0.03 ≈ 97%, a "perfect").
    MATCH_SPREAD  = 0.17
    PERFECT_MATCH = 97 # % shown as "Perfect!" on the phones and the TV

    # A streak: STREAK_LENGTH rounds in a row at STREAK_MATCH % or more pays STREAK_BONUS, and so does
    # every round after it while the streak lasts.
    STREAK_MATCH  = 85
    STREAK_LENGTH = 3
    STREAK_BONUS  = 150

    # Named colours for the reveal ("It was Coral · you made Salmon"): the nearest one by eye (OKLab).
    # Names are in the JS locale files: js.guess_the_color.colors.<key>.
    COLOR_NAMES = {
      "red" => [ 220, 40, 40 ], "crimson" => [ 160, 20, 40 ], "maroon" => [ 110, 20, 30 ], "pink" => [ 245, 160, 190 ],
      "hot_pink" => [ 240, 80, 160 ], "salmon" => [ 245, 130, 110 ], "coral" => [ 250, 110, 80 ], "orange" => [ 245, 140, 30 ],
      "peach" => [ 250, 195, 150 ], "rust" => [ 170, 70, 30 ], "brown" => [ 130, 80, 40 ], "tan" => [ 210, 170, 120 ],
      "beige" => [ 230, 215, 185 ], "cream" => [ 250, 240, 210 ], "gold" => [ 230, 180, 30 ], "yellow" => [ 250, 235, 0 ],
      "lemon" => [ 245, 240, 140 ], "khaki" => [ 190, 180, 110 ], "olive" => [ 120, 120, 40 ], "lime" => [ 160, 220, 40 ],
      "green" => [ 40, 160, 60 ], "forest_green" => [ 30, 90, 40 ], "mint" => [ 160, 230, 190 ], "teal" => [ 20, 130, 130 ],
      "turquoise" => [ 60, 210, 200 ], "cyan" => [ 40, 200, 230 ], "sky_blue" => [ 120, 190, 240 ], "blue" => [ 40, 90, 220 ],
      "navy" => [ 20, 30, 90 ], "indigo" => [ 70, 40, 150 ], "purple" => [ 130, 50, 170 ], "violet" => [ 170, 110, 220 ],
      "lavender" => [ 200, 180, 240 ], "magenta" => [ 210, 40, 190 ], "plum" => [ 120, 40, 90 ], "white" => [ 245, 245, 245 ],
      "light_grey" => [ 200, 200, 200 ], "grey" => [ 128, 128, 128 ], "charcoal" => [ 60, 60, 65 ], "black" => [ 15, 15, 15 ]
    }.transform_values { |(r, g, b)| { "r" => r, "g" => g, "b" => b } }.freeze

    # Easy mode: 12 vivid hues spaced 30° apart, full saturation, mid lightness
    EASY_HUES = (0..330).step(30).to_a.freeze

    # Round modes: memory (the colour shows, then goes), blink (it shows for a moment), match (it
    # stays on the TV while players pick) and real_world (no colour: the TV names an everyday thing).
    # christmas works like real_world with Christmas things (config/guess_the_color/christmas.yml).
    MODES      = %w[memory blink match real_world christmas].freeze
    SHOW_TIMES = { "memory" => 5, "blink" => 1, "match" => 3, "real_world" => 5, "christmas" => 5 }.freeze
    REAL_WORLD = YAML.load_file(Rails.root.join("config/guess_the_color/real_world.yml")).freeze
    CHRISTMAS  = YAML.load_file(Rails.root.join("config/guess_the_color/christmas.yml")).freeze
    THINGS     = { "real_world" => REAL_WORLD, "christmas" => CHRISTMAS }.freeze # the modes that name a thing

    # End-of-game awards: "most creative" goes to the furthest pick, if one was under this % match.
    CREATIVE_BELOW = 50

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
          "mode"          => MODES.include?(@room.game_state["mode"]) ? @room.game_state["mode"] : "memory",
          "used_prompts"  => [],
          "history"       => {}, # player id => % match per round (nil: no pick), for the awards
          "pick_time"     => self.class.pick_time(@room.game_state["pick_time"]),
          "scores"        => scores,
          "current_color" => nil,
          "picks"         => {},
          "round_scores"  => {},
          "streaks"       => {}
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

    def mode
      @room.game_state["mode"] || "memory"
    end

    def show_time
      SHOW_TIMES.fetch(mode, SHOW_TIMES["memory"])
    end

    # The next round's target: { color:, prompt: } (prompt only in real_world/christmas mode, in the room's
    # language). Real-world things don't repeat in a game until they've all been used.
    def next_target!
      things = THINGS[mode]
      return { color: generate_color, prompt: nil } unless things

      used = @room.game_state["used_prompts"].to_a
      key  = (things.keys - used).sample || things.keys.sample
      @room.atomic_set("game_state.used_prompts" => (used | [ key ]), "game_state.prompt" => key)
      item = things[key]
      { color: %w[r g b].zip(item["rgb"]).to_h, prompt: item[@room.locale.to_s] || item["en"] }
    end

    # 🦅 best average match, 🎯 closest single pick, 🌈 furthest pick (if one was really far).
    def awards
      history = (@room.reload.game_state["history"] || {}).select { |_, matches| matches.compact.any? }
      return [] if history.empty?

      average = history.transform_values { |m| m.sum(&:to_i) / m.size.to_f }
      best    = history.flat_map { |id, m| m.compact.map { [ id, _1 ] } }
      list = [
        { "key" => "eagle_eye", "player_id" => average.max_by(&:last).first, "value" => average.values.max.round },
        { "key" => "bullseye", "player_id" => best.max_by(&:last).first, "value" => best.map(&:last).max }
      ]
      furthest = best.min_by(&:last)
      list << { "key" => "creative", "player_id" => furthest.first, "value" => furthest.last } if furthest.last < CREATIVE_BELOW
      list
    end

    # Scores the round's picks, adds streak bonuses, saves the totals and returns what the reveal shows.
    def score_round!
      @room.reload
      state   = @room.game_state
      target  = state["current_color"]
      picks   = state["picks"] || {}
      scores  = state["scores"] || {}
      streaks = state["streaks"] || {}
      history = state["history"] || {}
      round_scores, matches, bonuses = {}, {}, {}

      scores.each_key do |id|
        points = picks[id] ? self.class.calculate_score(target, picks[id]) : 0
        match  = self.class.match_percent(points)
        matches[id]  = match if picks[id]
        streaks[id]  = picks[id] && match >= STREAK_MATCH ? streaks[id].to_i + 1 : 0
        bonuses[id]  = STREAK_BONUS if streaks[id] >= STREAK_LENGTH
        round_scores[id] = points + bonuses[id].to_i
        scores[id]       = scores[id].to_i + round_scores[id]
        history[id]      = history[id].to_a + [ matches[id] ]
      end

      @room.atomic_set("game_state.scores" => scores, "game_state.round_scores" => round_scores,
                       "game_state.streaks" => streaks, "game_state.history" => history,
                       "game_state.status" => "revealing")
      {
        target_color: target,
        target_name:  self.class.color_name(target),
        picks:        picks,
        pick_names:   picks.transform_values { |pick| self.class.color_name(pick) },
        matches:      matches,
        bonuses:      bonuses,
        streaks:      streaks,
        round_scores: round_scores,
        scores:       scores,
        perfect:      PERFECT_MATCH
      }
    end

    # The key of the named colour that looks closest ("coral").
    def self.color_name(color)
      return nil unless color

      lab = oklab(color)
      COLOR_NAMES.min_by { |_, named| oklab(named).zip(lab).sum { |a, b| (a - b)**2 } }.first
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
