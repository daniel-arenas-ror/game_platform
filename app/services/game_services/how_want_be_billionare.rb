
module GameServices
  class HowWantBeBillionare < Base
    def initialize(room)
      @room = room
      @players = room.players.to_a
    end

    def setup_game!
      @room.update!(status: 'playing')
      start_points!
      update_question!

      broadcast_start
    end

    def next_round!
      calc_points!
      update_question!
    end

    def add_answer(player_id, choice)
      question_id = @room.game_state['question_id'].to_s
      player_id_str = player_id.to_s

      mongo_path = "game_state.answers_history.#{question_id}.#{player_id_str}"

      @room.set(mongo_path => choice)
    end

    private

    def update_question!
      question = ::HowWantBeBillionare::Question.collection.aggregate([{ '$sample': { size: 1 } }]).first

      @room.set("game_state.question_id" => question['_id'])
      @room.set("game_state.question" => question['text'])
      @room.set("game_state.answers" => question['answers'])
    end

    def calc_points!
      @room.reload
      question_id = @room.game_state['question_id'].to_s
      question = ::HowWantBeBillionare::Question.find(question_id)
      mongo_path = "game_state.answers_history.#{question_id}"
      question_answers = @room.game_state['answers_history'][question_id] ||= {}
      user_points = @room.game_state['user_points'] ||= {}

      question_answers.each do |player_id, answer_index|
        if question.answers[answer_index.to_i]["correct"]
          user_points[player_id] ||= 0
          user_points[player_id] += question.points
        end
      end

      @room.set("game_state.user_points" => user_points)
    end
  end
end
