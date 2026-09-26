
module GameServices
  class HowWantBeBillionare < Base
    def initialize(room)
      @room = room
      @players = room.players.to_a
    end

    def setup_game!
      @room.update!(status: 'playing')

      user_points = @players.each_with_object({}) { |p, h| h[p.id.to_s] = 0 }
      @room.atomic_set(
        'game_state.user_points'        => user_points,
        'game_state.asked_question_ids' => [],
        'game_state.answers_history'    => {}
      )

      update_question!
      broadcast_start
      true
    end

    # Score the current round; returns reveal data for broadcasting.
    def score_round!
      calc_points!
    end

    # Load the next question into game_state.
    def advance_question!
      update_question!
    end

    def add_answer(player_id, choice)
      question_id   = @room.game_state['question_id'].to_s
      player_id_str = player_id.to_s

      existing = @room.game_state.dig('answers_history', question_id, player_id_str)
      return if !existing.nil?

      @room.atomic_set("game_state.answers_history.#{question_id}.#{player_id_str}" => choice.to_i)
    end

    private

    def update_question!
      @room.reload
      asked_ids  = @room.game_state['asked_question_ids'] || []
      asked_oids = asked_ids.filter_map do |id|
        id.is_a?(BSON::ObjectId) ? id : BSON::ObjectId(id.to_s)
      rescue StandardError
        nil
      end

      pipeline = []
      pipeline << { '$match' => { '_id' => { '$nin' => asked_oids } } } unless asked_oids.empty?
      pipeline << { '$sample' => { size: 1 } }

      question = ::HowWantBeBillionare::Question.collection.aggregate(pipeline).first

      if question.nil?
        asked_ids = []
        @room.atomic_set('game_state.asked_question_ids' => [])
        question = ::HowWantBeBillionare::Question.collection.aggregate([{ '$sample' => { size: 1 } }]).first
      end

      @room.atomic_set(
        'game_state.question_id'        => question['_id'],
        'game_state.question'           => question['text'],
        'game_state.answers'            => question['answers'],
        'game_state.asked_question_ids' => asked_ids + [question['_id'].to_s]
      )
    end

    # Scores the current round and returns a hash with all data needed for the reveal broadcast.
    def calc_points!
      @room.reload
      question_id      = @room.game_state['question_id'].to_s
      question         = ::HowWantBeBillionare::Question.find(question_id)
      question_answers = @room.game_state.dig('answers_history', question_id) || {}
      user_points      = @room.game_state['user_points'] || {}
      round_scores     = {}

      correct_indices = question.answers.each_with_index
                        .select { |a, _| a['correct'] }
                        .map    { |_, i| i }

      question_answers.each do |player_id, answer_index|
        next unless correct_indices.include?(answer_index.to_i)

        user_points[player_id] ||= 0
        user_points[player_id] += question.points.to_i
        round_scores[player_id] = question.points.to_i
      end

      @room.atomic_set('game_state.user_points' => user_points)

      {
        round_scores:           round_scores,
        user_points:            user_points,
        correct_answer_indices: correct_indices,
        question_points:        question.points.to_i
      }
    end
  end
end
