module GameServices
  # Pictionary-style: each turn one player (the artist) draws a secret word on their phone, the strokes
  # appear on the TV only, and everyone else types guesses on their phone.
  class DoodleDash < Base
    DRAW_TIMES   = [ 40, 60, 80, 100 ].freeze
    TURN_CHOICES = [ 1, 2, 3 ].freeze      # how many times each player draws
    DIFFICULTIES = %w[easy medium hard mixed].freeze

    CHOOSE_TIME = 10 # seconds the artist has to pick a word, then one is picked at random
    CHOICES     = 3

    # A correct guess is worth 50–100 points, depending on how much drawing time was left.
    MIN_GUESS_POINTS = 50
    MAX_GUESS_POINTS = 100
    FIRST_GUESS_BONUS = 25  # the first player to guess the word
    ARTIST_SHARE      = 0.5 # the artist earns half of each guesser's points (25–50): clear drawings pay
    # Players who aren't drawing can send these; they float up over the drawing on the TV.
    REACTIONS = %w[😂 👏 🔥 🤯 🤔 ❤️].freeze

    # Game over: the TV shows every drawing and phones vote for the best one (not their own).
    VOTE_TIME           = 20
    BEST_DRAWING_POINTS = 100 # to the artist of the drawing with the most votes (all of them on a tie)
    MIN_VOTERS          = 3   # with 2 players each would just vote for the other

    MAX_GUESS_LENGTH = 40

    # Drawing. Points are fractions of the canvas (0–1); brush sizes are per 1000 px of canvas width.
    # #f8fafc is white paint (for snow on a blue sky); #ffffff, the paper, is the eraser.
    PALETTE     = %w[#111827 #ef4444 #f97316 #facc15 #22c55e #3b82f6 #a855f7 #92400e #f8fafc #ffffff].freeze
    BRUSH_SIZES = [ 4, 10, 24 ].freeze
    MAX_POINTS_PER_MESSAGE = 120  # one live batch
    MAX_STROKE_POINTS      = 2000 # one whole stroke
    MAX_STROKES            = 1500
    MAX_STROKE_ID          = 100_000

    # Word lists per room language: config/doodle_dash/words.yml (English) and words.<locale>.yml.
    WORDS = { "en" => "words.yml", "es" => "words.es.yml" }.transform_values do |file|
      YAML.load_file(Rails.root.join("config/doodle_dash", file)).transform_values(&:freeze).freeze
    end.freeze
    BLOCKED = YAML.load_file(Rails.root.join("config/doodle_dash/blocked_words.yml")).freeze

    # Word packs the host can pick instead of the classic lists: { pack => { locale => [words] } }.
    PACKS = YAML.load_file(Rails.root.join("config/doodle_dash/packs.yml")).transform_values(&:freeze).freeze
    # "mix" (the default): every pack plus the easy and medium classic words.
    WORD_SOURCES = [ "mix", "classic", *PACKS.keys ].freeze
    # The host's own words (typed in the settings, one per line or comma separated), on top of any
    # category: while some are unused, one of the artist's 3 choices each turn is one of them.
    MAX_CUSTOM_WORDS = 100
    MAX_CUSTOM_WORD  = 30 # letters

    # What the artist draws: words, players in the room (everyone guesses who), or a mix (the default:
    # every other turn is a player turn). Player turns need 3+ players, else it's a word.
    SUBJECTS           = %w[words players mix].freeze
    MIN_PLAYERS_TO_DRAW = 3

    # Fill bucket: a "stroke" with one point and fill: true, flood-filled on every screen.
    MAX_FILLS = 30 # per drawing: each one costs every screen a full-canvas pass when it redraws

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
      custom     = self.class.clean_custom_words(state["custom_words"])
      source     = WORD_SOURCES.include?(state["word_source"]) ? state["word_source"] : "mix"
      subject    = SUBJECTS.include?(state["subject"]) ? state["subject"] : "mix"
      order      = @players.map { |p| p.id.to_s }.shuffle

      @room.update!(
        status: "playing",
        game_state: state.except("word", "choices", "strokes", "guessed", "pattern").merge(
          "status"           => "waiting",
          "loop_running"     => false,
          "draw_time"        => draw_time,
          "turns_per_player" => laps,
          "difficulty"       => difficulty,
          "word_source"      => source,
          "subject"          => subject,
          "kind"             => "word", # this turn: "word" or "player"
          "custom_words"     => custom,
          "show_guesses"     => state["show_guesses"].to_s != "false",
          # Same order every lap, so everyone draws once before anyone draws twice.
          "turns"            => Array.new(laps) { order }.flatten,
          "turn"             => -1,
          "artist_id"        => nil,
          "used_words"       => [],
          "guessed"          => {},
          "strokes"          => [],
          "removed_strokes"  => [],
          "cleared_upto"     => 0,
          "pattern"          => nil,
          "artist_left"      => false,
          "drawings"         => [], # { turn, artist_id, word } for every turn that has a drawing
          "votes"            => {}, # voter id => turn
          "best_drawings"    => [],
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

      players = player_turn?(index) ? pick_players(artist_id) : []
      kind    = players.any? ? "player" : "word"
      choices = players.presence || pick_words
      @room.atomic_set(
        "game_state.status"         => "choosing",
        "game_state.kind"           => kind,
        "game_state.turn"           => index,
        "game_state.artist_id"      => artist_id,
        "game_state.choices"        => choices,
        "game_state.word"           => nil,
        "game_state.pattern"        => nil,
        "game_state.guessed"        => {},
        "game_state.first_guesser"  => nil,
        "game_state.artist_earned"  => 0,
        "game_state.strokes"        => [],
        "game_state.removed_strokes" => [],
        "game_state.cleared_upto"   => 0,
        "game_state.artist_left"    => false,
        "game_state.choose_ends_at" => Time.now.to_f + CHOOSE_TIME,
        "game_state.turn_ends_at"   => nil
      )
      { artist_id: artist_id, choices: choices, kind: kind }
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
          "game_state.pattern"      => word.chars.map { |c| c.match?(/[[:alnum:]]/) ? nil : c },
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
        artist = (points * ARTIST_SHARE).round
        filter = { "_id" => @room.id, "game_state.status" => "drawing", "game_state.turn" => state["turn"],
                   "game_state.guessed.#{pid}" => { "$exists" => false } }
        update = { "$set" => { "game_state.guessed.#{pid}" => points },
                   "$inc" => { "game_state.scores.#{pid}" => points, "game_state.scores.#{state['artist_id']}" => artist,
                               "game_state.artist_earned" => artist } }
        return { ok: false } unless apply(filter, update)

        first = claim_first_guess!(pid, state["turn"])
        points += FIRST_GUESS_BONUS if first
        { ok: true, result: "correct", points: points, first: first, word: word }
      elsif self.class.close?(text, word)
        { ok: true, result: "close" }
      else
        { ok: true, result: "wrong", text: self.class.feed_text(text) }
      end
    end

    # Only the first right guess of a turn gets the bonus, even when two arrive together.
    def claim_first_guess!(pid, turn)
      filter = { "_id" => @room.id, "game_state.turn" => turn, "game_state.first_guesser" => nil }
      update = { "$set" => { "game_state.first_guesser" => pid },
                 "$inc" => { "game_state.scores.#{pid}" => FIRST_GUESS_BONUS, "game_state.guessed.#{pid}" => FIRST_GUESS_BONUS } }
      return false unless apply(filter, update)

      @room.reload
      true
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

    # Ends the turn and returns what the reveal shows. A turn with a drawing goes in the gallery.
    def end_turn!
      @room.reload
      word = @room.game_state["word"]
      @room.atomic_set("game_state.status" => "reveal", "game_state.pattern" => word.to_s.chars)
      state = @room.game_state
      if state["strokes"].present?
        entry = { "turn" => state["turn"], "artist_id" => state["artist_id"], "word" => word, "kind" => state["kind"] }
        Room.collection.update_one({ "_id" => @room.id }, { "$push" => { "game_state.drawings" => entry } })
      end

      {
        word:          word,
        artist_id:     state["artist_id"],
        artist_points: state["artist_earned"].to_i,
        kind:          state["kind"],
        first_guesser: state["first_guesser"],
        guessed:       state["guessed"].to_h,
        scores:        state["scores"].to_h
      }
    end

    # ── Gallery vote ─────────────────────────────────────────────────────────

    # True when there's something to vote on: 2+ drawings and enough players to make it fair.
    def voting?
      @room.reload
      @room.game_state["drawings"].to_a.size >= 2 && @room.players.count >= MIN_VOTERS
    end

    def open_vote!
      @room.atomic_set("game_state.status" => "voting", "game_state.votes" => {},
                       "game_state.vote_ends_at" => Time.now.to_f + VOTE_TIME)
    end

    # A vote for drawing `turn`. Not for your own, and once only. Returns true when it counted.
    def vote!(player_id, turn)
      pid     = player_id.to_s
      drawing = fresh_state["drawings"].to_a.find { |d| d["turn"] == turn.to_i }
      return false unless drawing && drawing["artist_id"] != pid

      filter = { "_id" => @room.id, "game_state.status" => "voting", "game_state.votes.#{pid}" => { "$exists" => false } }
      apply(filter, { "$set" => { "game_state.votes.#{pid}" => drawing["turn"] } })
    end

    def votes_count
      fresh_state["votes"].to_h.size
    end

    # Every connected player who has someone else's drawing to vote for has voted.
    def all_voted?
      state   = fresh_state
      artists = state["drawings"].to_a.map { |d| d["artist_id"] }
      voters  = Player.where(room_id: @room.id, connected: true).pluck(:id).map(&:to_s).select { |id| (artists - [ id ]).any? }
      voters.any? && (voters - state["votes"].to_h.keys).empty?
    end

    # Counts the votes, pays the artist(s) of the winning drawing(s) and returns them.
    def tally_votes!
      @room.reload
      state  = @room.game_state
      counts = state["votes"].to_h.values.tally
      top    = counts.values.max.to_i
      best   = state["drawings"].to_a.select { |d| top.positive? && counts[d["turn"]] == top }
                                     .map { |d| d.merge("votes" => top) }
      scores = state["scores"].to_h
      best.each { |d| scores[d["artist_id"]] = scores[d["artist_id"]].to_i + BEST_DRAWING_POINTS if scores.key?(d["artist_id"]) }
      @room.atomic_set("game_state.best_drawings" => best, "game_state.scores" => scores)
      best
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

    # Phone messages can be handled out of order (ActionCable runs them on a thread pool), so every
    # stroke has an id from the phone, and saving, undo and clear each work whatever came first:
    # a stroke that was undone or cleared before it was saved is never saved.

    # Saves a finished stroke ({ "id", "color", "size", "points" }), so a reloaded TV or artist
    # phone can redraw everything. Saving the same stroke twice does nothing.
    def save_stroke!(player_id, stroke)
      return false unless stroke
      return false if stroke["fill"] && fresh_state["strokes"].to_a.count { |s| s["fill"] } >= MAX_FILLS

      id     = stroke["id"]
      filter = artist_filter(player_id).merge(
        "game_state.strokes.id"         => { "$ne" => id },
        "game_state.removed_strokes"    => { "$ne" => id },
        "game_state.cleared_upto"       => { "$lt" => id }
      )
      apply(filter, "$push" => { "game_state.strokes" => { "$each" => [ stroke ], "$slice" => -MAX_STROKES } })
    end

    def undo!(player_id, id)
      apply(artist_filter(player_id), "$pull" => { "game_state.strokes" => { "id" => id } },
                                      "$addToSet" => { "game_state.removed_strokes" => id })
    end

    # Removes every stroke up to id `upto`, the last one the artist saw when they tapped Clear.
    def clear!(player_id, upto)
      apply(artist_filter(player_id), "$pull" => { "game_state.strokes" => { "id" => { "$lte" => upto } } },
                                      "$max" => { "game_state.cleared_upto" => upto })
    end

    def self.clean_stroke_id(id)
      id.is_a?(Integer) && id.between?(0, MAX_STROKE_ID) ? id : nil
    end

    # Cleans points from the phone: [[x, y], …] clamped to the canvas, or nil if invalid.
    def self.clean_points(points, max = MAX_POINTS_PER_MESSAGE)
      return nil unless points.is_a?(Array) && points.length.between?(1, max)

      points.map do |point|
        return nil unless point.is_a?(Array) && point.length == 2 && point.all?(Numeric)

        point.map { |v| v.to_f.clamp(0.0, 1.0).round(4) }
      end
    end

    def self.clean_style(color, size)
      return nil unless PALETTE.include?(color) && BRUSH_SIZES.include?(size)

      { "color" => color, "size" => size }
    end

    # The host's typed list: one word or phrase per line (or comma), trimmed, lowercase, no repeats,
    # nothing the TV feed would hide.
    def self.clean_custom_words(text)
      list = text.is_a?(Array) ? text : text.to_s.split(/[\n,;]+/)
      list.map { |word| word.to_s.squish.downcase }
          .select { |word| word.length.between?(2, MAX_CUSTOM_WORD) && normalize(word).present? && feed_text(word) != "***" }
          .uniq { |word| normalize(word) }
          .first(MAX_CUSTOM_WORDS)
    end

    # ── Guess matching ───────────────────────────────────────────────────────

    # Lowercase, no accents or punctuation, single spaces, no leading article (English or Spanish).
    def self.normalize(text)
      text.to_s.unicode_normalize(:nfkd).gsub(/\p{Mn}/, "").downcase
          .gsub(/[^a-z0-9\s]/, "").squish.sub(/\A(a|an|the|el|la|los|las|un|una|unos|unas) /, "")
    end

    # Spaces don't matter ("hotdog" = "hot dog") and plurals count ("cats" for "cat").
    def self.correct?(guess, word)
      g = normalize(guess).delete(" ")
      w = normalize(word).delete(" ")
      return false if g.empty?

      g == w || g == "#{w}s" || g == "#{w}es" || w == "#{g}s" || w == "#{g}es"
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
      shown = state.except(*SECRET_KEYS, "strokes", "turns", "used_words", "loop_running", "votes", "custom_words")
      shown["votes_count"] = state["votes"].to_h.size
      shown["total_turns"] = total_turns
      shown["word"] = state["word"] if %w[reveal game_over].include?(state["status"])
      shown
    end

    # The TV also gets the strokes, to redraw after a reload.
    def host_state
      public_state.merge("strokes" => @room.game_state["strokes"].to_a)
    end

    # The artist's phone also gets their word choices, or their word and their own drawing so far
    # (to carry on after a reload).
    def player_state(player_id)
      shown = public_state
      shown["my_vote"] = @room.game_state.dig("votes", player_id.to_s)
      return shown unless player_id.to_s == @room.game_state["artist_id"]

      case @room.game_state["status"]
      when "choosing" then shown["choices"] = @room.game_state["choices"]
      when "drawing"  then shown.merge!("word" => @room.game_state["word"], "strokes" => @room.game_state["strokes"].to_a)
      end
      shown
    end

    private

    # Three unused words. "mixed" offers one easy, one medium and one hard word.
    def player_turn?(index)
      case @room.game_state["subject"]
      when "players" then true
      when "mix"     then index.odd?
      else false
      end
    end

    # Up to 3 players connected right now, never the artist, whose name can be typed. Players not
    # drawn yet come first, so nobody is drawn twice before everyone has been drawn once.
    # Empty when the room is too small (the turn uses words instead).
    def pick_players(artist_id)
      players = Player.where(room_id: @room.id).to_a
      return [] if players.size < MIN_PLAYERS_TO_DRAW

      drawn = @room.game_state["used_words"].to_a
      names = players.select { |p| p.connected && p.id.to_s != artist_id.to_s && self.class.normalize(p.nickname).present? }
                     .map(&:nickname).uniq
      (names - drawn).shuffle.first(CHOICES).then { |fresh| fresh + (names - fresh).shuffle.first(CHOICES - fresh.size) }
    end

    def pick_words
      used   = @room.game_state["used_words"].to_a
      words  = WORDS.fetch(@room.locale, WORDS["en"])
      source = @room.game_state["word_source"]
      pack   = ->(name) { PACKS[name].fetch(@room.locale, PACKS[name]["en"]) }
      pools =
        if PACKS.key?(source)
          Array.new(CHOICES) { pack.(source) }
        elsif source == "classic" && @room.game_state["difficulty"] == "mixed"
          %w[easy medium hard].map { |level| words[level] }
        elsif source == "classic"
          Array.new(CHOICES) { words[@room.game_state["difficulty"]] }
        else
          mix = (PACKS.keys.flat_map(&pack) + words["easy"] + words["medium"]).uniq
          Array.new(CHOICES) { mix }
        end

      own = @room.game_state["custom_words"].to_a - used
      pools[0] = own if own.any?

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
