module GameServices
  class HowWantBeBillionare < Base
    DEFAULT_ROUNDS   = 10                    # what the settings start on
    DEFAULT_SECONDS  = 10
    SPEED_FLOOR      = 0.5                   # a right answer at the buzzer keeps half its points
    STREAKS          = { 5 => 2, 3 => 1.5 }.freeze # right answers in a row → points multiplier
    FINAL_MULTIPLIER = 2                     # the last question is worth double
    POINTS_LADDER    = (100..1000).step(100).to_a.freeze
    BET_FRACTIONS    = [ 0, 0.25, 0.5, 1 ].freeze # share of your points you can bet on the final question
    # Question packs (the import's file names) the host can pick from; nil = all of them.
    PACKS = %w[christmas general_knowledge history geography science biology food sports literature
               art_and_music math_and_technology mythology_and_language].freeze

    def initialize(room)
      @room = room
      @players = room.players.to_a
    end

    # keep_asked_questions: on "Play Again", skip questions already used earlier in this room.
    def setup_game!(keep_asked_questions: false)
      @room.update!(status: 'playing')

      asked_ids   = keep_asked_questions ? (@room.game_state['asked_question_ids'] || []) : []
      user_points = @players.each_with_object({}) { |p, h| h[p.id.to_s] = 0 }
      @room.atomic_set(
        'game_state.user_points'        => user_points,
        'game_state.asked_question_ids' => asked_ids,
        'game_state.answers_history'    => {},
        'game_state.answer_seconds'     => {},
        'game_state.streaks'            => {},
        'game_state.bets'               => {},
        'game_state.fifty'              => {},
        'game_state.fastest'            => {},
        'game_state.best_streaks'       => {},
        'game_state.worst_ranks'        => {},
        'game_state.screen'             => nil
      )

      update_question!(0)
      broadcast_start
      true
    end

    def total_rounds
      rounds = @room.game_state['total_rounds'].to_i
      rounds < 1 ? DEFAULT_ROUNDS : rounds
    end

    def final_round?(round)
      round == total_rounds - 1
    end

    # What the current question is worth, before speed and streaks.
    def question_points(round)
      points = @room.game_state['question_points'].to_i
      points = POINTS_LADDER.first if points <= 0
      final_round?(round) ? points * FINAL_MULTIPLIER : points
    end

    # The clock starts when the question goes out; answers are timed from here.
    def start_question!(duration)
      @room.atomic_set('game_state.question_started_at' => Time.current.to_f, 'game_state.question_duration' => duration)
    end

    # Every player still connected has answered, so the round can end before the time is up.
    def everyone_answered?
      @room.reload
      answered = (@room.game_state.dig('answers_history', @room.game_state['question_id'].to_s) || {}).keys
      connected_ids.any? && (connected_ids - answered).empty?
    end

    # ── Final bet ──────────────────────────────────────────────────────────
    # Before the final question each player bets a share of their points: won back on a right
    # answer, lost on a wrong one (or none). Players with no points have nothing to bet.

    def bets_open?
      total_rounds > 1
    end

    def place_bet!(player_id, fraction)
      fraction = fraction.to_f
      return unless BET_FRACTIONS.include?(fraction)

      @room.reload
      id = player_id.to_s
      return if @room.game_state.dig('bets', id)

      amount = (@room.game_state.dig('user_points', id).to_i * fraction / 10.0).round * 10
      @room.atomic_set("game_state.bets.#{id}" => amount)
      amount
    end

    def bets_placed
      (@room.reload.game_state['bets'] || {}).size
    end

    def everyone_bet?
      @room.reload
      points = @room.game_state['user_points'] || {}
      waiting = connected_ids.select { |id| points[id].to_i.positive? } - (@room.game_state['bets'] || {}).keys
      waiting.empty?
    end

    # ── 50:50 ─────────────────────────────────────────────────────────────
    # Once per game a player can take away up to two wrong answers on their phone. At least one
    # wrong answer always stays. Returns the removed indices, or nil when it can't be used.
    def use_fifty!(player_id)
      @room.reload
      id          = player_id.to_s
      question_id = @room.game_state['question_id'].to_s
      return if @room.game_state.dig('fifty', id)
      return unless @room.game_state.dig('answers_history', question_id, id).nil?

      wrong   = (@room.game_state['answers'] || []).each_with_index.reject { |a, _| a['correct'] }.map(&:last)
      removed = wrong.sample([ wrong.size - 1, 2 ].min).sort
      @room.atomic_set("game_state.fifty.#{id}" => { 'question_id' => question_id, 'removed' => removed })
      removed
    end

    # The answers this player took away on the current question (for a phone that reconnects).
    def fifty_removed(player_id)
      used = @room.game_state.dig('fifty', player_id.to_s)
      used['removed'] if used && used['question_id'] == @room.game_state['question_id'].to_s
    end

    # ── Awards (game over) ──────────────────────────────────────────────────

    def awards
      @room.reload
      state  = @room.game_state
      points = state['user_points'] || {}
      list   = []

      fastest = (state['fastest'] || {}).min_by { |_, seconds| seconds.to_f }
      list << { 'key' => 'fastest', 'player_id' => fastest[0], 'seconds' => fastest[1] } if fastest

      streak = (state['best_streaks'] || {}).max_by { |_, best| best.to_i }
      list << { 'key' => 'streak', 'player_id' => streak[0], 'count' => streak[1] } if streak && streak[1].to_i >= 3

      climbs = (state['worst_ranks'] || {}).to_h { |id, worst| [ id, worst.to_i - rank_of(points, id) ] }
      comeback = climbs.max_by { |_, climb| climb }
      if comeback && comeback[1] >= 2
        list << { 'key' => 'comeback', 'player_id' => comeback[0],
                  'from' => state['worst_ranks'][comeback[0]], 'to' => rank_of(points, comeback[0]) }
      end
      list
    end

    # Score the current round; returns reveal data for broadcasting.
    def score_round!(round)
      calc_points!(round)
    end

    # Load the next question into game_state.
    def advance_question!(round)
      update_question!(round)
    end

    def add_answer(player_id, choice)
      question_id   = @room.game_state['question_id'].to_s
      player_id_str = player_id.to_s

      existing = @room.game_state.dig('answers_history', question_id, player_id_str)
      return if !existing.nil?

      started = @room.game_state['question_started_at'].to_f
      seconds = started.positive? ? (Time.current.to_f - started).round(2) : nil
      @room.atomic_set("game_state.answers_history.#{question_id}.#{player_id_str}" => choice.to_i,
                       "game_state.answer_seconds.#{question_id}.#{player_id_str}"  => seconds)
    end

    private

    def connected_ids
      @room.players.where(connected: true).pluck(:id).map(&:to_s)
    end

    # 1 + how many have more points (ties share a place).
    def rank_of(points, id)
      1 + points.count { |other, p| other != id && p.to_i > points[id].to_i }
    end

    # Questions climb the points ladder as the game goes on: cheap ones first, the most valuable at
    # the end. Falls back to any question not asked yet, then starts over when all were asked.
    def update_question!(round)
      @room.reload
      asked_ids  = @room.game_state['asked_question_ids'] || []
      asked_oids = asked_ids.filter_map do |id|
        id.is_a?(BSON::ObjectId) ? id : BSON::ObjectId(id.to_s)
      rescue StandardError
        nil
      end

      language  = ::HowWantBeBillionare::Question.match_for(@room.locale)
      pack      = @room.game_state['pack'].presence
      language  = language.merge('pack' => pack) if pack && ::HowWantBeBillionare::Question.where(language).where(pack: pack).exists?
      not_asked = asked_oids.empty? ? [] : [ { '$match' => { '_id' => { '$nin' => asked_oids } } } ]
      target    = ladder_points(round)
      near      = { '$match' => { 'points' => { '$gte' => target - 100, '$lte' => target + 100 } } }
      sample    = { '$sample' => { size: 1 } }
      questions = ::HowWantBeBillionare::Question.collection

      question = questions.aggregate([ { "$match" => language }, *not_asked, near, sample ]).first ||
                 questions.aggregate([ { "$match" => language }, *not_asked, sample ]).first

      if question.nil?
        asked_ids = []
        @room.atomic_set('game_state.asked_question_ids' => [])
        question = questions.aggregate([ { "$match" => language }, near, sample ]).first ||
                   questions.aggregate([ { "$match" => language }, sample ]).first
      end

      @room.atomic_set(
        'game_state.question_id'        => question['_id'],
        'game_state.question'           => question['text'],
        'game_state.answers'            => question['answers'],
        'game_state.question_points'    => question['points'],
        'game_state.asked_question_ids' => asked_ids + [question['_id'].to_s]
      )
    end

    # Round 1 aims at 100 points, the last round at 1000, evenly in between.
    def ladder_points(round)
      progress = total_rounds > 1 ? round.to_f / (total_rounds - 1) : 1.0
      POINTS_LADDER[(progress * (POINTS_LADDER.size - 1)).round]
    end

    # The player now alone at the top, when that's someone other than before. Nil otherwise.
    def new_leader(before, after)
      leader = ->(points) do
        top = points.values.map(&:to_i).max
        ids = points.select { |_, p| p.to_i == top }.keys
        ids.first if top.to_i.positive? && ids.size == 1
      end
      now = leader.(after)
      now if now && now != leader.(before)
    end

    def streak_multiplier(streak)
      STREAKS.find { |length, _| streak >= length }&.last || 1
    end

    # A right answer earns the question's points, less the slower it came (down to SPEED_FLOOR at
    # the buzzer), times the streak multiplier. A wrong answer or none breaks the streak.
    # Returns everything the reveal broadcast needs.
    def calc_points!(round)
      @room.reload
      question_id      = @room.game_state['question_id'].to_s
      question         = ::HowWantBeBillionare::Question.find(question_id)
      question_answers = @room.game_state.dig('answers_history', question_id) || {}
      answer_seconds   = @room.game_state.dig('answer_seconds', question_id) || {}
      duration         = @room.game_state['question_duration'].to_f
      user_points      = @room.game_state['user_points'] || {}
      streaks          = @room.game_state['streaks'] || {}
      bets             = final_round?(round) ? (@room.game_state['bets'] || {}) : {}
      fastest          = @room.game_state['fastest'] || {}
      best_streaks     = @room.game_state['best_streaks'] || {}
      worth            = question_points(round)
      previous_points  = user_points.dup
      round_scores     = {}
      round_details    = {}

      correct_indices = question.answers.each_with_index
                        .select { |a, _| a['correct'] }
                        .map    { |_, i| i }

      (user_points.keys | question_answers.keys).each do |player_id|
        answer = question_answers[player_id]
        bet    = bets[player_id].to_i
        unless answer && correct_indices.include?(answer.to_i)
          streaks[player_id] = 0
          if bet.positive?
            user_points[player_id]   = [ user_points[player_id].to_i - bet, 0 ].max
            round_details[player_id] = { 'bet' => -bet }
          end
          next
        end

        seconds    = answer_seconds[player_id]
        late       = duration.positive? && seconds ? (seconds.to_f / duration).clamp(0, 1) : 0
        streak     = streaks[player_id].to_i + 1
        multiplier = streak_multiplier(streak)
        points     = (worth * (1 - (1 - SPEED_FLOOR) * late) * multiplier / 10.0).round * 10

        streaks[player_id]       = streak
        user_points[player_id]   = user_points[player_id].to_i + points + bet
        round_scores[player_id]  = points + bet
        round_details[player_id] = { 'seconds' => seconds, 'streak' => streak, 'multiplier' => multiplier }
        round_details[player_id]['bet'] = bet if bet.positive?
        fastest[player_id]       = [ fastest[player_id], seconds ].compact.map(&:to_f).min if seconds
        best_streaks[player_id]  = [ best_streaks[player_id].to_i, streak ].max
      end

      # For the comeback award: the lowest place each player has been in (from round 2 on).
      worst_ranks = @room.game_state['worst_ranks'] || {}
      if round.positive?
        user_points.each_key { |id| worst_ranks[id] = [ worst_ranks[id].to_i, rank_of(user_points, id) ].max }
      end

      @room.atomic_set('game_state.user_points' => user_points, 'game_state.streaks' => streaks,
                       'game_state.fastest' => fastest, 'game_state.best_streaks' => best_streaks,
                       'game_state.worst_ranks' => worst_ranks)

      {
        answer_counts:          question.answers.each_index.map { |i| question_answers.values.count { |a| a.to_i == i } },
        previous_points:        previous_points,
        new_leader:             new_leader(previous_points, user_points),
        round_scores:           round_scores,
        round_details:          round_details,
        streaks:                streaks,
        user_points:            user_points,
        correct_answer_indices: correct_indices,
        question_points:        worth
      }
    end
  end
end
