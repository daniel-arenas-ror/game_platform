class Games::FishermanChannel < ApplicationCable::Channel
  def subscribed
    p " subscribed to fisherman channel "
    p " params: #{params.inspect} "

    @room = Room.find_by(code: params[:room_code])
    @player = Player.where(id: params[:player_id]).first
    @player.update(connected: true) if @player

    broadcast_presence(true) if @player
    stream_from "fisherman_room_#{@room.code}"
  end

  def unsubscribed
    p " unsubscribed "
    p " params: #{params.inspect} "

    @player = Player.where(id: params[:player_id]).first
    @player.update(connected: false) if @player

    broadcast_presence(false) if @player
  end

  def submit_guess(data)
    p " submit_guess with data: #{data.inspect} "
    @room = Room.find_by(code: params[:room_code])
    fisherman = GameServices::Fisherman.new(@room)
    fisherman.handle_guess!(data["target_ids"], params["player_id"])

    p " Broadcasting next_round_started for room: #{@room.code} "

    ActionCable.server.broadcast("fisherman_room_#{@room.code}", { 
      action: "next_round_started" 
    })
  end

  def broadcast_presence(is_online)
    p " broadcast_presence "
    ActionCable.server.broadcast("fisherman_room_#{@room.code}", {
      action: "player_presence",
      player_id: @player.id.to_s,
      connected: is_online
    })
  end

  def restart_game
    room = Room.find_by(code: params[:room_code])
    manager = GameServices::Fisherman.new(room)

    # 1. Reset the entire room state
    manager.setup_game!

    # 2. Broadcast the refresh signal to everyone
    ActionCable.server.broadcast("fisherman_room_#{room.code}", { 
      action: "next_round_started" 
    })
  end
end
