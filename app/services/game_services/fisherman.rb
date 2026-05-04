module GameServices
  class Fisherman < Base
    def initialize(room)
      @room = room
      @players = room.players.to_a
    end

    def setup_game!
      rotate_roles!
      update_question!

      broadcast_start

      true
    end

    def handle_guess!(target_ids, fisherman_id)
      calc_points!(target_ids, fisherman_id)
      rotate_roles!
      update_question!
      update_round!
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

    def update_round!
      @room.set("game_state.round" => @room.game_state["round"].to_i - 1)
      if @room.game_state["round"].to_i <= 0
        @room.update!(status: 'finished')

        points_hash = @room.game_state['points'] || {}
        @sorted_players = @room.players.sort_by do |player|
          points_hash[player.id.to_s].to_i
        end.reverse

        @room.set("game_state.sorted_players" => @sorted_players.map { |p| { nickname: p.nickname, points: points_hash[p.id.to_s].to_i } })
      end
    end

    def broadcast_start
      ActionCable.server.broadcast("game_#{@room.code}", {
        action: "game_started",
      })
    end
  end
end
