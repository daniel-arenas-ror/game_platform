# Room-wide news for the shared "Players" panel (shared/_room_players), on the lobby and on every
# game screen: players joining and leaving. A removed player's phone hears it here and leaves.
# It doesn't count towards a player's presence; the lobby and game channels do that.
class RoomChannel < ApplicationCable::Channel
  def self.stream_for_room(code)
    "room_#{code}"
  end

  def subscribed
    find_player
    return if subscription_rejected?

    stream_from self.class.stream_for_room(params[:room_code])
  end
end
