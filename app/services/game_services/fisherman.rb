module GameServices
  class Fisherman < Base
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
      @room.update!(status: 'playing', game_state: {
        question: "Leader famous that get scared the cats?",
        answereds: ["Napoleón Bonaparte", "Julio César", "Mussolini"],
        points: {
          @players.collect{|p| [p.id.to_s, 0]}.to_h
        }
      })

      broadcast_start

      true
    end

    private

    def broadcast_start
      ActionCable.server.broadcast("game_#{@room.code}", {
        action: "game_started",
      })
    end
  end
end
