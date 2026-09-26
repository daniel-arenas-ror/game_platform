module GameServices
  class MindMatch < Base
    DEFAULT_ROUNDS     = 5
    DEFAULT_TIME       = 15  # seconds players have to type a word

    CATEGORIES = [
      # Everyday / concrete
      "Things you find in a kitchen",
      "Things you find at the beach",
      "Things inside a backpack",
      "Things you see at a birthday party",
      "Things in a supermarket",
      "Things you do on a Sunday morning",
      "Things that are cold",
      "Things that are loud",
      "Things that are yellow",
      "Things you put on bread",
      "Things you find in a park",
      "Things in a car",
      "Things that have wheels",
      "Things you do before bed",
      # Pop culture / fun
      "Famous duos",
      "Things that are overrated",
      "Things people say when they're nervous",
      "Things you'd bring to a desert island",
      "Things a superhero would carry",
      "Words that sound funny",
      "Things that are better with cheese",
      "Reasons to call in sick to work",
      "Things you'd find in a wizard's bag",
      # Abstract / creative
      "Things that move fast",
      "Things that make you happy",
      "Things that are worse than Mondays",
      "Things that smell amazing",
      "Things you do when you're bored",
      "Things that are addictive",
      "Things people lie about",
      "Things that are hard to explain",
      "Things you miss from childhood",
      "Things money can't buy",
      "Things that are a waste of time",
      "Things you'd never eat",
      "Things that are always late",
      "Things that belong in a museum",
      "Things that are impossible to resist",
      "Things that are surprisingly satisfying"
    ].freeze

    def initialize(room)
      @room    = room
      @players = room.players.to_a
    end

    def setup_game!
      total_rounds = (@room.game_state["total_rounds"] || DEFAULT_ROUNDS).to_i
      time_per_round = (@room.game_state["time_per_round"] || DEFAULT_TIME).to_i
      scores = @players.each_with_object({}) { |p, h| h[p.id.to_s] = 0 }

      @room.update!(
        status: "playing",
        game_state: @room.game_state.merge(
          "status"           => "waiting",
          "round"            => 0,
          "total_rounds"     => total_rounds,
          "time_per_round"   => time_per_round,
          "scores"           => scores,
          "used_categories"  => [],
          "answers"          => {},
          "round_scores"     => {},
          "loop_running"     => false,
          "current_category" => nil
        )
      )

      broadcast_start
      true
    end

    # Returns a category not yet used this game. Falls back to any category if all used.
    def pick_category!
      @room.reload
      used = @room.game_state["used_categories"] || []
      available = CATEGORIES - used
      available = CATEGORIES if available.empty?

      category = available.sample
      @room.atomic_set(
        "game_state.used_categories"   => used + [category],
        "game_state.answers"           => {},
        "game_state.current_category"  => category
      )
      category
    end

    # Groups answers, scores players. Returns { groups, round_scores, scores, answers }.
    # Groups: [ { word: "sand", player_ids: [...] }, ... ] sorted by group size desc.
    def score_round!
      @room.reload
      answers      = @room.game_state["answers"]   || {}
      scores       = @room.game_state["scores"]    || {}
      round_scores = {}

      # Normalize and group: { normalised_word => [player_id, ...] }
      groups = {}
      answers.each do |player_id, raw_word|
        next if raw_word.to_s.strip.empty?
        word = normalize_word(raw_word)
        groups[word] ||= []
        groups[word] << player_id
      end

      # Award N points to each member of a group of size N
      groups.each do |_word, player_ids|
        n = player_ids.size
        player_ids.each do |player_id|
          round_scores[player_id] = n
          scores[player_id] = scores[player_id].to_i + n
        end
      end

      # Players who didn't submit get 0
      scores.each_key do |player_id|
        round_scores[player_id] ||= 0
      end

      @room.atomic_set(
        "game_state.scores"       => scores,
        "game_state.round_scores" => round_scores
      )

      # Return groups as array sorted by size desc, keeping original casing from first submitter
      display_groups = groups.map do |word, player_ids|
        original = answers.find { |_, v| normalize_word(v) == word }&.last || word
        { "word" => original, "player_ids" => player_ids }
      end.sort_by { |g| -g["player_ids"].size }

      { groups: display_groups, round_scores: round_scores, scores: scores, answers: answers }
    end

    # Saves the player's word only while the round is collecting and they haven't answered yet.
    # A single conditional update, so concurrent submissions can't overwrite each other.
    # Returns true if the answer was stored.
    def add_answer(player_id, word)
      key = "game_state.answers.#{player_id}"
      result = Room.collection.update_one(
        { "_id" => @room.id, "game_state.status" => "collecting", key => { "$exists" => false } },
        { "$set" => { key => word.to_s.strip.first(30) } }
      )
      result.modified_count == 1
    end

    private

    # Normalize a word for matching: lowercase, collapse spaces, strip leading/trailing
    # punctuation, and fold common English plurals (strip trailing 's' for words > 4 chars
    # that don't already end in 'ss', 'us', 'is', 'as', 'os').
    def normalize_word(raw)
      w = raw.to_s
             .downcase
             .strip
             .gsub(/[[:punct:]]+\z/, "")   # strip trailing punctuation
             .gsub(/\A[[:punct:]]+/, "")   # strip leading punctuation
             .gsub(/\s+/, " ")             # collapse internal spaces

      # Fold common English plurals: "cats" → "cat", but keep "grass", "plus", "virus"
      if w.length > 4 && w.end_with?("s") && !w.end_with?("ss", "us", "is", "as", "os")
        w = w.chomp("s")
      end

      w
    end
  end
end
