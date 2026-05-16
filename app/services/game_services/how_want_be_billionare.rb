
module GameServices
  class HowWantBeBillionare < Base
    def initialize(room)
      @room = room
      @players = room.players.to_a
    end

    def setup_game!

      
    end
  end
end
