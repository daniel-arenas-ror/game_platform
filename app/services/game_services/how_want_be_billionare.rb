
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

    private

    def update_question!
      question = ::HowWantBeBillionare::Question.collection.aggregate([{ '$sample': { size: 1 } }]).first

      @room.set("game_state.question" => question['text'])
      @room.set("game_state.answerds" => question['answerds'])
    end
  end
end
