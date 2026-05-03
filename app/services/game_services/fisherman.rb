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


      @room.update!(status: 'playing', game_state: {
        question: "Leader famous that get scared the cats?",
        answereds: ["Napoleón Bonaparte", "Julio César", "Mussolini"],
        points: @players.collect{|p| [p.id.to_s, 0]}.to_h
      })

      broadcast_start

      true
    end

    def handle_guess!(target_ids, fisherman_id)
      calc_points!(target_ids, fisherman_id)
      rotate_roles!
      update_question!
    end

    private

    def calc_points!(target_ids, fisherman_id)
      points = @room.game_state["points"]
      target_ids.map do |id|
        player = @room.players.find(id)

        if player.role == 'impostor'
          points[fisherman_id] += 1
        else
          points[id] += 1
        end
      end

      @room.set("game_state.points" => points)
    end

    def rotate_roles!
      shuffled = @players.shuffle
      
      fisherman = shuffled.shift
      impostor = shuffled.shift
      knowers = shuffled

      fisherman.update!(role: 'fisherman')
      impostor.update!(role: 'impostor')
      knowers.each { |p| p.update!(role: 'knower') }
    end

    def update_question!
      @room.set("game_state.question" => "Leader famous that get scared the cats?")
      @room.set("game_state.answereds" => ["Napoleón Bonaparte", "Julio César", "Mussolini"])
    end

    def broadcast_start
      ActionCable.server.broadcast("game_#{@room.code}", {
        action: "game_started",
      })
    end
  end
end
