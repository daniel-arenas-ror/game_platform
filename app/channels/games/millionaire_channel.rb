class Games::MillionaireChannel < ApplicationCable::Channel

  def subscribed
    p "params: #{params.inspect}"

    @room = Room.find_by(code: params[:room_code])
    @player = Player.where(id: params[:player_id]).first
    @player.update(connected: true) if @player

    p " @room.code "
    p @room.code

    broadcast_presence(true) if @player

    stream_from "millionaire_room_#{@room.code}"
  end

  def unsubscribed
    if @player
      @player.update(connected: false)
      broadcast_presence(false)
    end
  end

  def broadcast_presence(is_online)
    ActionCable.server.broadcast("millionaire_room_#{@room.code}", {
      action: "player_presence",
      player_id: @player.id.to_s,
      connected: is_online
    })
  end

  def start_game_loop
    @room = Room.find_by(code: params[:room_code])

    Thread.new do
      # number of rounds
      total_rounds = @room.game_state["total_rounds"].to_i || 5
      total_rounds.times do |index|
        GameServices::HowWantBeBillionare.new(@room).next_round!
        @room.reload

        question_data = {
          action: "send_question",
          text: @room.game_state["question"],
          options: @room.game_state["answers"]
        }

        ActionCable.server.broadcast("millionaire_room_#{@room.code}", question_data)

        sleep @room.game_state["time_per_round"].to_i || 10
      end

      # @room.update(status: 'finished')
      ActionCable.server.broadcast("millionaire_room_#{@room.code}", {
        action: "show_leaderboard",
        leaderboard: @room.game_state["user_points"] || {}
      })
    end
  end

  def submit_millionaire_answer(data)
    GameServices::HowWantBeBillionare.new(@room.reload).add_answer(@player.id, data["choice"])
  end
end
