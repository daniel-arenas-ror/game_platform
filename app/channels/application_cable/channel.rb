module ApplicationCable
  class Channel < ActionCable::Channel::Base
    private

    # Finds the subscribing player. A player_id that no longer exists (the player was removed
    # after disconnecting) is rejected, so a stale phone can't fall through to host privileges.
    def find_player
      return nil if params[:player_id].blank?

      player = Player.where(id: params[:player_id]).first
      reject unless player
      player
    end

    # Subscriptions are counted rather than flagged: when a page reloads, the new subscription
    # can be processed before the old one's unsubscribe, and a boolean would end up false.
    def track_player_subscribed(player)
      return unless player

      Player.collection.update_one({ _id: player.id }, { "$inc" => { "connections" => 1 }, "$set" => { "connected" => true } })
    end

    def track_player_unsubscribed(player)
      return unless player

      doc = Player.collection.find_one_and_update(
        { _id: player.id }, { "$inc" => { "connections" => -1 } }, return_document: :after
      )
      return unless doc && doc["connections"].to_i <= 0

      Player.collection.update_one({ _id: player.id, "connections" => { "$lte" => 0 } }, { "$set" => { "connected" => false } })
      PlayerRemover.schedule(player.id)
    end
  end
end
