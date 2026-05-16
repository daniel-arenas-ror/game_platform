module GameServices
  class Base

    def start_points!
      points_hash = @players.each_with_object({}) do |player, hash|
        hash[player.id.to_s] = 0
      end

      @room.set("game_state.points" => points_hash)
    end

    def broadcast_start
      ActionCable.server.broadcast("game_#{@room.code}", {
        action: "game_started",
      })
    end
  end
end
