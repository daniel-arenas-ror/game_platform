module GameServices
  class Base

    def start_points!
      points_hash = @players.each_with_object({}) do |player, hash|
        hash[player.id.to_s] = 0
      end

      @room.atomic_set("game_state.points" => points_hash)
    end

    # Hook for PlayerRemover. The player is already deleted and their game_state entries dropped;
    # override when the game can't carry on without extra work (e.g. re-assigning roles).
    def player_removed!(_player_id); end

    def broadcast_start
      ActionCable.server.broadcast("game_#{@room.code}", {
        action: "game_started",
      })
    end
  end
end
