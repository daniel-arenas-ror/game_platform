class Games::FishermanChannel < ApplicationCable::Channel
  def subscribed
    room = Room.find_by(code: params[:room_code])
    stream_from "fisherman_room_#{room.code}"
  end

  def unsubscribed
    # Any cleanup needed when channel is unsubscribed
  end

  def submit_answer(data)
    room = Room.find_by(code: params[:room_code])
    # Use your Service Manager to handle the logic
    manager = GameServices::ImpostorManager.new(room)
    manager.handle_answer(current_player, data['answer'])
  end
end
