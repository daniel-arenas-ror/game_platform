module GameServices
  # Pictionary-style: each turn one player (the artist) draws a secret word on their phone, the strokes
  # appear on the TV only, and everyone else types guesses on their phone.
  class DoodleDash < Base
    DRAW_TIMES   = [ 60, 80, 100 ].freeze
    TURN_CHOICES = [ 1, 2, 3 ].freeze      # how many times each player draws
    DIFFICULTIES = %w[easy medium hard mixed].freeze

    CHOOSE_TIME = 10 # seconds the artist has to pick a word, then one is picked at random
    CHOICES     = 3

    # A correct guess is worth 50–100 points, depending on how much drawing time was left.
    MIN_GUESS_POINTS = 50
    MAX_GUESS_POINTS = 100
    ARTIST_POINTS    = 25 # for every player who guesses the word

    MAX_GUESS_LENGTH = 40

    # Drawing. Points are fractions of the canvas (0–1); brush sizes are per 1000 px of canvas width.
    PALETTE     = %w[#111827 #ef4444 #f97316 #facc15 #22c55e #3b82f6 #a855f7 #92400e #ffffff].freeze
    BRUSH_SIZES = [ 4, 10, 24 ].freeze
    MAX_POINTS_PER_MESSAGE = 120
    MAX_STROKES = 1500

    WORDS   = YAML.load_file(Rails.root.join("config/doodle_dash/words.yml")).transform_values(&:freeze).freeze
    BLOCKED = YAML.load_file(Rails.root.join("config/doodle_dash/blocked_words.yml")).freeze

    # Never sent to guessers or the TV while a turn is being played.
    SECRET_KEYS = %w[word choices].freeze

    def initialize(room)
      @room    = room
      @players = room.players.to_a
    end

    def setup_game!
      state      = @room.game_state
      draw_time  = state["draw_time"].to_i
      draw_time  = 80 unless DRAW_TIMES.include?(draw_time)
      laps       = state["turns_per_player"].to_i
      laps       = 1 unless TURN_CHOICES.include?(laps)
      difficulty = DIFFICULTIES.include?(state["difficulty"]) ? state["difficulty"] : "mixed"
      order      = @players.map { |p| p.id.to_s }.shuffle

      @room.update!(
        status: "playing",
        game_state: state.except("word", "choices", "strokes", "guessed", "pattern").merge(
          "status"           => "waiting",
          "loop_running"     => false,
          "draw_time"        => draw_time,
          "turns_per_player" => laps,
          "difficulty"       => difficulty,
          "show_guesses"     => state["show_guesses"].to_s != "false",
          # Same order every lap, so everyone draws once before anyone draws twice.
          "turns"            => Array.new(laps) { order }.flatten,
          "turn"             => -1,
          "artist_id"        => nil,
          "used_words"       => [],
          "guessed"          => {},
          "strokes"          => [],
          "pattern"          => nil,
          "artist_left"      => false,
          "scores"           => @players.to_h { |p| [ p.id.to_s, 0 ] }
        )
      )

      broadcast_start
      true
    end

    def total_turns
      @room.game_state["turns"].to_a.length
    end

    # Starts turn `index` (0-based): the artist gets 3 words to choose from.
    # Returns { artist_id:, choices: }, or nil when that artist has left the room (skip the turn).
    def start_turn!(index)
      @room.reload
      artist_id = @room.game_state["turns"].to_a[index]
      return nil unless artist_id && Player.where(_id: artist_id, room_id: @room.id).exists?

      choices = pick_words
      @room.atomic_set(
        "game_state.status"         => "choosing",
        "game_state.turn"           => index,
        "game_state.artist_id"      => artist_id,
        "game_state.choices"        => choices,
        "game_state.word"           => nil,
        "game_state.pattern"        => nil,
        "game_state.guessed"        => {},
        "game_state.strokes"        => [],
        "game_state.artist_left"    => false,
        "game_state.choose_ends_at" => Time.now.to_f + CHOOSE_TIME,
        "game_state.turn_ends_at"   => nil
      )
      { artist_id: artist_id, choices: choices }
    end

    # The artist picks choice `index`, or the loop picks one at random when time runs out
    # (player_id nil). Whichever comes first wins. Returns the word, or nil if it was too late.
    def choose_word!(player_id, index = nil)
      @room.reload
      state   = @room.game_state
      choices = state["choices"].to_a
      index   = Integer(index, exception: false) || rand(choices.length)
      word    = choices[index]
      return nil unless state["status"] == "choosing" && word
      return nil if player_id && player_id.to_s != state["artist_id"]

      filter = { "_id" => @room.id, "game_state.status" => "choosing", "game_state.turn" => state["turn"] }
      update = {
        "$set"  => {
          "game_state.status"       => "drawing",
          "game_state.word"         => word,
          "game_state.pattern"      => word.chars.map { |c| c.match?(/[a-z0-9]/) ? nil : c },
          "game_state.turn_ends_at" => Time.now.to_f + state["draw_time"].to_i
        },
        "$push" => { "game_state.used_words" => word }
      }
      return nil unless apply(filter, update)

      @room.reload
      word
    end

    # A guess from a player's phone. Returns { ok: false } when it can't be taken (not drawing, the
    # artist, already guessed, blank), else { ok: true, result: "correct" | "close" | "wrong", … }.
    def guess!(player_id, text)
      @room.reload
      state = @room.game_state
      pid   = player_id.to_s
      text  = text.to_s.squish[0, MAX_GUESS_LENGTH]
      word  = state["word"]

      return { ok: false } unless state["status"] == "drawing" && word && text.present?
      return { ok: false } if pid == state["artist_id"] || state["guessed"].to_h.key?(pid)

      if self.class.correct?(text, word)
        left   = state["turn_ends_at"].to_f - Time.now.to_f
        points = guess_points(left, state["draw_time"].to_i)
        filter = { "_id" => @room.id, "game_state.status" => "drawing", "game_state.turn" => state["turn"],
                   "game_state.guessed.#{pid}" => { "$exists" => false } }
        update = { "$set" => { "game_state.guessed.#{pid}" => points },
                   "$inc" => { "game_state.scores.#{pid}" => points, "game_state.scores.#{state['artist_id']}" => ARTIST_POINTS } }
        return { ok: false } unless apply(filter, update)

        { ok: true, result: "correct", points: points, word: word }
      elsif self.class.close?(text, word)
        { ok: true, result: "close" }
      else
        { ok: true, result: "wrong", text: self.class.feed_text(text) }
      end
    end

    # Reveals one more letter of the word on the TV, keeping at least two letters hidden.
    # Returns the new pattern, or nil when no letter can be revealed.
    def reveal_hint!
      @room.reload
      state   = @room.game_state
      pattern = state["pattern"].to_a.dup
      word    = state["word"]
      hidden  = pattern.each_index.select { |i| pattern[i].nil? }
      return nil unless state["status"] == "drawing" && word && hidden.length > 2

      i = hidden.sample
      pattern[i] = word[i]
      @room.atomic_set("game_state.pattern" => pattern)
      pattern
    end

    # True when every player except the artist has guessed the word.
    def all_guessed?
      state    = fresh_state
      guessers = Player.where(room_id: @room.id).pluck(:id).map(&:to_s) - [ state["artist_id"] ]
      guessers.any? && guessers.all? { |pid| state["guessed"].to_h.key?(pid) }
    end

    def artist_left?
      fresh_state["artist_left"] == true
    end

    # Ends the turn and returns what the reveal shows.
    def end_turn!
      @room.reload
      word = @room.game_state["word"]
      @room.atomic_set("game_state.status" => "reveal", "game_state.pattern" => word.to_s.chars)
      state = @room.game_state

      {
        word:      word,
        artist_id: state["artist_id"],
        guessed:   state["guessed"].to_h,
        scores:    state["scores"].to_h
      }
    end

    def finish_game!
      @room.reload
      @room.update!(status: "finished", game_state: @room.game_state.merge("status" => "game_over", "loop_running" => false))
    end

    # ── Drawing ──────────────────────────────────────────────────────────────

    # True while `player_id` is the artist of a turn that is being drawn.
    def drawing_artist?(player_id)
      state = fresh_state
      state["status"] == "drawing" && state["artist_id"] == player_id.to_s
    end

    # Saves a finished stroke, so a TV that reloads mid-turn can redraw everything.
    def save_stroke!(player_id, stroke)
      return false unless stroke

      apply(artist_filter(player_id),
            "$push" => { "game_state.strokes" => { "$each" => [ stroke ], "$slice" => -MAX_STROKES } })
    end

    def undo!(player_id)
      apply(artist_filter(player_id), "$pop" => { "game_state.strokes" => 1 })
    end

    def clear!(player_id)
      apply(artist_filter(player_id), "$set" => { "game_state.strokes" => [] })
    end

    # Cleans a batch of points from the phone: [[x, y], …] clamped to the canvas, or nil if invalid.
    def self.clean_points(points)
      return nil unless points.is_a?(Array) && points.length.between?(1, MAX_POINTS_PER_MESSAGE)

      points.map do |point|
        return nil unless point.is_a?(Array) && point.length == 2 && point.all?(Numeric)

        point.map { |v| v.to_f.clamp(0.0, 1.0).round(4) }
      end
    end

    def self.clean_style(color, size)
      return nil unless PALETTE.include?(color) && BRUSH_SIZES.include?(size)

      { "color" => color, "size" => size }
    end

    # ── Guess matching ───────────────────────────────────────────────────────

    # Lowercase, no accents or punctuation, single spaces, no leading article.
    def self.normalize(text)
      text.to_s.unicode_normalize(:nfkd).gsub(/\p{Mn}/, "").downcase
          .gsub(/[^a-z0-9\s]/, "").squish.sub(/\A(a|an|the) /, "")
    end

    # Spaces don't matter ("hotdog" = "hot dog") and plurals count ("cats" for "cat").
    def self.correct?(guess, word)
      g = normalize(guess).delete(" ")
      w = normalize(word).delete(" ")
      return false if g.empty?

      g == w || g == "#{w}s" || g == "#{w}es" || w == "#{g}s"
    end

    # One letter off (or two neighbours swapped, the usual phone typo) on a word of 4+ letters.
    def self.close?(guess, word)
      g = normalize(guess).delete(" ")
      w = normalize(word).delete(" ")
      return false if w.length < 4 || g == w

      DidYouMean::Levenshtein.distance(g, w) == 1 || swapped_neighbours?(g, w)
    end

    def self.swapped_neighbours?(a, b)
      return false unless a.length == b.length

      diff = (0...a.length).reject { |i| a[i] == b[i] }
      diff.length == 2 && diff[1] == diff[0] + 1 && a[diff[0]] == b[diff[1]] && a[diff[1]] == b[diff[0]]
    end

    # A wrong guess as the TV feed shows it: "***" when it contains a blocked word.
    def self.feed_text(text)
      tokens = normalize(text).split
      blocked = tokens.any? do |token|
        BLOCKED.any? { |entry| entry.end_with?("*") ? token.start_with?(entry.delete_suffix("*")) : token == entry }
      end
      blocked ? "***" : text.to_s.squish[0, MAX_GUESS_LENGTH]
    end

    # ── Players leaving ──────────────────────────────────────────────────────

    # Takes the player out of the turns still to come; if they were drawing, the loop ends the turn.
    def player_removed!(player_id)
      @room.reload
      pid   = player_id.to_s
      state = @room.game_state
      index = state["turn"].to_i
      turns = state["turns"].to_a
      done  = index >= 0 ? turns[0..index] : []
      rest  = turns[(index + 1)..].to_a.reject { |id| id == pid }

      fields = { "game_state.turns" => done + rest }
      fields["game_state.artist_left"] = true if state["artist_id"] == pid && %w[choosing drawing].include?(state["status"])
      @room.atomic_set(fields)
    end

    # ── What each screen may see ─────────────────────────────────────────────

    # Guessers' phones: no word, no choices, no strokes (the drawing is on the TV only).
    def public_state
      state = @room.game_state
      shown = state.except(*SECRET_KEYS, "strokes", "turns", "used_words", "loop_running")
      shown["total_turns"] = total_turns
      shown["word"] = state["word"] if %w[reveal game_over].include?(state["status"])
      shown
    end

    # The TV also gets the strokes, to redraw after a reload.
    def host_state
      public_state.merge("strokes" => @room.game_state["strokes"].to_a)
    end

    # The artist's phone also gets their word choices or their word.
    def player_state(player_id)
      shown = public_state
      return shown unless player_id.to_s == @room.game_state["artist_id"]

      shown["choices"] = @room.game_state["choices"] if @room.game_state["status"] == "choosing"
      shown["word"]    = @room.game_state["word"] if @room.game_state["status"] == "drawing"
      shown
    end

    private

    # Three unused words. "mixed" offers one easy, one medium and one hard word.
    def pick_words
      used = @room.game_state["used_words"].to_a
      pools =
        if @room.game_state["difficulty"] == "mixed"
          %w[easy medium hard].map { |level| WORDS[level] }
        else
          Array.new(CHOICES) { WORDS[@room.game_state["difficulty"]] }
        end

      pools.each_with_object([]) do |pool, picked|
        fresh = pool - used - picked
        picked << (fresh.presence || pool - picked).sample
      end
    end

    def guess_points(seconds_left, draw_time)
      share = draw_time.positive? ? seconds_left / draw_time : 0
      (MIN_GUESS_POINTS + (MAX_GUESS_POINTS - MIN_GUESS_POINTS) * share).round.clamp(MIN_GUESS_POINTS, MAX_GUESS_POINTS)
    end

    def artist_filter(player_id)
      { "_id" => @room.id, "game_state.status" => "drawing", "game_state.artist_id" => player_id.to_s }
    end

    def fresh_state
      Room.where(_id: @room.id).only(:game_state).first&.game_state || {}
    end

    def apply(filter, update)
      Room.collection.update_one(filter, update).modified_count == 1
    end
  end
end
