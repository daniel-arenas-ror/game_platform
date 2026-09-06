class Games::BattleCityChannel < ApplicationCable::Channel
  STREAM_PREFIX = "battle_city_room_"

  def subscribed
    @room   = Room.find_by(code: params[:room_code])
    @player = Player.where(id: params[:player_id]).first if params[:player_id].present?

    @player&.update(connected: true)

    stream_from "#{STREAM_PREFIX}#{@room.code}"

    # Send the current full game state to the new subscriber only
    transmit({ action: "state_snapshot", state: @room.game_state })
  end

  def unsubscribed
    return unless @player

    @player.update(connected: false)
    ActionCable.server.broadcast("#{STREAM_PREFIX}#{@room.code}", {
      action: "player_presence",
      player_id: @player.id.to_s,
      connected: false
    })
  end
end
