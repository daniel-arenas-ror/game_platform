
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
      update_question!
      calc_points!
    end

    def add_answer(player_id, choice)
      @room.set("game_state.answers_history.#{@room.game_state['question_id']}" => { player_id: player_id, choice: choice })
    end

    private

    def update_question!
      question = ::HowWantBeBillionare::Question.collection.aggregate([{ '$sample': { size: 1 } }]).first

      @room.set("game_state.question_id" => question['_id'])
      @room.set("game_state.question" => question['text'])
      @room.set("game_state.answers" => question['answers'])
    end

    def calc_points!
      
    end
  end
end
