module GameServices
  # The TV goes round the alphabet: each letter has a clue ("Starts with A: …" or "Contains X: …") and
  # every phone answers the same word at once, one try each. A right answer scores BASE_POINTS plus up
  # to SPEED_POINTS for answering fast. The winner has the most words right; points break ties.
  # The answers stay on the server until each word's reveal: see #public_state.
  class LetterWheel < Base
    ALPHABETS = {
      "en" => ("a".."z").to_a,
      "es" => ("a".."n").to_a + [ "ñ" ] + ("o".."z").to_a
    }.transform_values(&:freeze).freeze

    # Clues per room language and level: config/letter_wheel/words.<locale>.yml (everyday words, ages 8+)
    # and hard.<locale>.yml (general knowledge: history, science, geography, culture).
    LEVEL_FILES = { "easy" => "words", "hard" => "hard" }.freeze
    WORDS = ALPHABETS.keys.to_h do |locale|
      [ locale, LEVEL_FILES.transform_values do |file|
        YAML.load_file(Rails.root.join("config/letter_wheel/#{file}.#{locale}.yml")).transform_values(&:freeze).freeze
      end.freeze ]
    end.freeze

    TIME_CHOICES   = [ 10, 15, 20, 30 ].freeze # seconds per word
    DEFAULT_TIME   = 20
    LENGTH_CHOICES = %w[short full].freeze     # short: SHORT_LETTERS random letters, full: the alphabet
    DEFAULT_LENGTH = "short"
    LEVEL_CHOICES  = %w[easy hard mix].freeze  # mix: each letter's clue from both lists
    DEFAULT_LEVEL  = "easy"
    SHORT_LETTERS  = 12

    BASE_POINTS  = 100
    SPEED_POINTS = 100

    TYPO_MIN_LENGTH = 6 # one wrong, missing or extra letter is forgiven from this length on
    ARTICLES = {
      "en" => /\A(the|an|a) /,
      "es" => /\A(el|la|los|las|un|una|unos|unas) /
    }.freeze

    INTERNAL_KEYS = %w[words answers loop_id loop_beat].freeze
    REVEALED      = %w[reveal game_over].freeze

    attr_reader :room

    def initialize(room)
      @room    = room
      @players = room.players.to_a
    end

    def setup_game!
      word_time = @room.game_state["word_time"].to_i
      word_time = DEFAULT_TIME unless TIME_CHOICES.include?(word_time)
      length    = @room.game_state["length"].to_s
      length    = DEFAULT_LENGTH unless LENGTH_CHOICES.include?(length)
      level     = @room.game_state["level"].to_s
      level     = DEFAULT_LEVEL unless LEVEL_CHOICES.include?(level)
      words     = self.class.pick_words(locale, length, level)

      @room.update!(
        status: "playing",
        game_state: @room.game_state.merge(
          "phase"         => "waiting",
          "loop_id"       => nil,
          "loop_beat"     => nil,
          "round"         => 0,
          "word_time"     => word_time,
          "length"        => length,
          "level"         => level,
          "letters"       => words.map { _1["letter"] },
          "words"         => words,
          "phase_ends_at" => nil,
          "scores"        => @players.to_h { |p| [ p.id.to_s, 0 ] },
          "correct"       => @players.to_h { |p| [ p.id.to_s, 0 ] },
          "results"       => {},
          "round_points"  => {},
          "answers"       => {}
        )
      )

      broadcast_start
      true
    end

    # One random clue per letter, in alphabet order. Short games take SHORT_LETTERS of the letters.
    def self.pick_words(locale, length, level = DEFAULT_LEVEL)
      alphabet = ALPHABETS[locale]
      letters  = length == "full" ? alphabet : alphabet.sample(SHORT_LETTERS).sort_by { alphabet.index(_1) }
      letters.map do |letter|
        lists = level == "mix" ? WORDS[locale].values : [ WORDS[locale].fetch(level) ]
        word  = lists.flat_map { _1.fetch(letter) }.sample
        { "letter" => letter, "answer" => word["answer"], "also" => Array(word["also"]),
          "clue" => word["clue"], "contains" => word["contains"] == true }
      end
    end

    # A guess, compared like WordMatch plus without a leading article; one typo is forgiven on long words.
    def self.right_answer?(guess, word, locale)
      guess = comparable(guess, locale)
      return false if guess.empty?

      [ word["answer"], *word["also"] ].any? do |answer|
        answer = comparable(answer, locale)
        guess == answer || (answer.length >= TYPO_MIN_LENGTH && DidYouMean::Levenshtein.distance(guess, answer) <= 1)
      end
    end

    def self.comparable(text, locale)
      WordMatch.fold(WordMatch.clean(text).sub(ARTICLES[locale], ""), locale)
    end

    # BASE_POINTS, plus SPEED_POINTS shrinking to 0 as the word's time runs out.
    def self.points_for(seconds_left, word_time)
      BASE_POINTS + (SPEED_POINTS * (seconds_left.to_f / word_time).clamp(0, 1)).round
    end

    # Player ids, best first: most words right, then points.
    def self.ranking(state)
      state["scores"].to_h.keys.sort_by { |pid| [ -state["correct"].to_h[pid].to_i, -state["scores"][pid].to_i ] }
    end

    # A player who came in from the QR during the game.
    def join!(player_id)
      apply({ "_id" => @room.id, "game_state.scores.#{player_id}" => { "$exists" => false } },
            "$set" => { "game_state.scores.#{player_id}" => 0, "game_state.correct.#{player_id}" => 0 })
    end

    def start_round!(round)
      @room.atomic_set("game_state.phase" => "clue", "game_state.round" => round, "game_state.answers" => {},
                       "game_state.round_points" => {},
                       "game_state.phase_ends_at" => Time.now.to_f + @room.game_state["word_time"].to_i)
    end

    # One try per player while the clue is up. Returns { "right", "points" }, or nil when it doesn't count.
    def answer!(player_id, text)
      text = text.to_s.strip.first(40)
      return nil if text.empty? || @room.game_state["phase"] != "clue"

      right  = self.class.right_answer?(text, current_word, locale)
      result = { "text" => text, "right" => right,
                 "points" => right ? self.class.points_for(seconds_left_f, @room.game_state["word_time"].to_i) : 0 }

      saved = apply({ "_id" => @room.id, "game_state.phase" => "clue", "game_state.round" => @room.game_state["round"],
                      "game_state.scores.#{player_id}" => { "$exists" => true },
                      "game_state.answers.#{player_id}" => { "$exists" => false } },
                    "$set" => { "game_state.answers.#{player_id}" => result })
      saved ? result.slice("right", "points") : nil
    end

    def all_answered?
      state = @room.class.where(id: @room.id).only(:game_state).first&.game_state.to_h
      ids   = state["scores"].to_h.keys
      ids.any? && (ids - state["answers"].to_h.keys).empty?
    end

    # Closes the phones first, so an answer can't land while the points are counted.
    def score_round!
      return false unless apply({ "_id" => @room.id, "game_state.phase" => "clue" }, "$set" => { "game_state.phase" => "scoring" })

      state   = @room.game_state
      answers = state["answers"].to_h
      players = state["scores"].to_h.keys
      points  = players.to_h { |pid| [ pid, answers.dig(pid, "points").to_i ] }
      right   = players.select { |pid| answers.dig(pid, "right") }

      updates = players.to_h { |pid| [ "game_state.scores.#{pid}", state["scores"][pid].to_i + points[pid] ] }
      right.each { |pid| updates["game_state.correct.#{pid}"] = state["correct"].to_h[pid].to_i + 1 }

      @room.atomic_set(updates.merge(
        "game_state.round_points" => points,
        "game_state.results.#{current_word["letter"]}" => players.empty? ? 0 : (right.size.to_f / players.size).round(2),
        "game_state.phase" => "reveal", "game_state.phase_ends_at" => nil
      ))
      true
    end

    def finish_game!
      @room.reload
      @room.update!(status: "finished", game_state: @room.game_state.merge("phase" => "game_over", "phase_ends_at" => nil))
    end

    def current_word
      @room.game_state["words"].to_a[@room.game_state["round"].to_i - 1] || {}
    end

    # What every screen may see: the clue, and the answer (with who got it) only once the word is over.
    def public_state
      state = @room.game_state
      shown = state.except(*INTERNAL_KEYS)
      word  = current_word

      shown["total_rounds"] = state["words"].to_a.size
      shown["letter"]       = word["letter"]
      shown["clue"]         = word["clue"]
      shown["contains"]     = word["contains"]
      shown["answered"]     = state["answers"].to_h.keys
      shown["seconds_left"] = seconds_left_f&.ceil
      if REVEALED.include?(shown["phase"])
        shown["answer"]  = word["answer"]
        shown["guesses"] = state["answers"].to_h.transform_values { _1.slice("text", "right") }
      end
      if shown["phase"] == "game_over"
        shown["solutions"] = state["words"].to_a.map { _1.slice("letter", "answer") }
        shown["ranking"]   = self.class.ranking(state)
      end
      shown
    end

    private

    def locale
      WORDS.key?(@room.locale.to_s) ? @room.locale.to_s : "en"
    end

    def seconds_left_f
      ends_at = @room.game_state["phase_ends_at"]
      ends_at ? [ ends_at - Time.now.to_f, 0 ].max : nil
    end

    def apply(filter, update)
      changed = Room.collection.update_one(filter, update).modified_count == 1
      @room.reload if changed
      changed
    end
  end
end
