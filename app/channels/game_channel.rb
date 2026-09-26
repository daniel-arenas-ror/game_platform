class GameChannel < ApplicationCable::Channel
  def subscribed
    @player = find_player
    return if subscription_rejected?

    track_player_subscribed(@player)
    stream_from "game_#{params[:room_code]}"
  end

  def unsubscribed
    track_player_unsubscribed(@player)
  end
end
