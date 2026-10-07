module GameServices
  class Base
    # Every game's setup_game! (the first start from the lobby and each "play again") is counted
    # for the admin stats, wrapped here so no game can forget it.
    module TrackStart
      def setup_game!(...)
        again  = @room.status != "lobby"
        result = super
        if @room.status == "playing"
          Event.record(:game_started, room: @room, players: @room.players.count, again: again)
        end
        result
      end
    end

    def self.inherited(game)
      super
      game.prepend(TrackStart)
    end

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
