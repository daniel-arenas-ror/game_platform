class Games::FishermanChannel < ApplicationCable::Channel
  def subscribed
    p " subscribed to fisherman channel "
    room = Room.find_by(code: params[:room_code])
    player = Player.find(params[:player_id])
    player.update(connected: true)

    stream_from "fisherman_room_#{room.code}"
  end

  def unsubscribed
    p " unsubscribed "
    p " params: #{params.inspect} "

    player = Player.find(params[:player_id])
    player.update(connected: false)

    # Any cleanup needed when channel is unsubscribed
  end

  def submit_answer(data)
    room = Room.find_by(code: params[:room_code])
    # Use your Service Manager to handle the logic
    manager = GameServices::ImpostorManager.new(room)
    manager.handle_answer(current_player, data['answer'])
  end

  def submit_guess(data)
    @room = Room.find_by(code: params[:room_code])
    fisherman = GameServices::Fisherman.new(@room)
    fisherman.handle_guess!(data[:target_ids], current_player.id.to_s)

    ActionCable.server.broadcast("fisherman_room_#{room.code}", { 
      action: "next_round_started" 
    })
  end
end
