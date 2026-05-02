module GameServices
  class FishermanManager
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

      # 2. Pick a random word for the knowers
      word = ["Shark", "Anchor", "Submarine", "Coral"].sample
      @room.update!(status: 'playing', game_state: { secret_word: word })

      # 3. Broadcast specific roles to specific players
      broadcast_roles(fisherman, impostor, knowers, word)
    end

    private

    def broadcast_roles(f, i, ks, word)
      # Logic to send private WebSockets to each role
      # The fisherman sees "You are the Fisherman"
      # The knowers see "The word is: Shark"
      # The impostor sees "You are the Impostor"
    end
  end
end
