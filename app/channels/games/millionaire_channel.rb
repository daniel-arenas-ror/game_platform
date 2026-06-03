class Games::MillionaireChannel < ApplicationCable::Channel

  def subscribed

    p "params: #{params.inspect}"

    @room = Room.find_by(code: params[:room_code])
    @player = Player.where(id: params[:player_id]).first
    @player.update(connected: true) if @player

    p " @room.code "
    p @room.code

    broadcast_presence(true) if @player

    stream_from "fisherman_room_#{@room.code}"
  end

  def unsubscribed
  end

  def broadcast_presence(is_online)
    ActionCable.server.broadcast("fisherman_room_#{@room.code}", {
      action: "player_presence",
      player_id: @player.id.to_s,
      connected: is_online
    })
  end

  def start_game_loop
    @room = Room.find_by(code: params[:room_code])

    Thread.new do
      # Let's say a game lasts 5 questions
      5.times do |index|
        # 1. Grab your question details from your game engine or DB pool
        # For testing, we generate dynamic placeholders:
        question_data = {
          action: "send_question",
          number: index + 1,
          text: "This is automated question number #{index + 1}?",
          options: {
            A: "Option Alpha",
            B: "Option Beta",
            C: "Option Gamma",
            D: "Option Delta"
          }
        }

        # 2. Shackle the payload out to every connected client socket
        ActionCable.server.broadcast("millionaire_room_#{@room.code}", question_data)

        # 3. Halt thread execution for exactly 10 seconds before looping
        sleep 10
      end

      # 4. Once loops conclude, switch everyone to the scoreboard layout
      ActionCable.server.broadcast("millionaire_room_#{@room.code}", { action: "show_leaderboard" })
    end
  end
end
