module GameServices
  class FishermanManager < Base
    def initialize(room)
      @room = room
      @players = room.players.to_a
    end

    def setup_game!
      shuffled = @players.shuffle
      
      fisherman = shuffled.shift
      impostor = shuffled.shift
      knowers = shuffled

      fisherman.update!(role: 'fisherman')
      impostor.update!(role: 'impostor')
      knowers.each { |p| p.update!(role: 'knower') }

      word = ["Shark", "Anchor", "Submarine", "Coral"].sample
      @room.update!(status: 'playing', game_state: { secret_word: word })

      broadcast_start(fisherman, impostor, knowers, secret_word)
      true
    end

    private

    def broadcast_start
      ActionCable.server.broadcast("game_#{@room.code}", {
        action: "game_started",
        view: "impostor_main_table"
      })

      @players.each do |player|
        # We send a "ping" to each player's specific channel or 
        # a general broadcast that triggers a role-check.
        ActionCable.server.broadcast("game_#{@room.code}", {
          action: "reveal_roles"
        })
      end
    end
  end
end
