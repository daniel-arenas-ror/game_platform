class Games::MillionaireChannel < ApplicationCable::Channel

  def subscribed
    @room   = Room.find_by(code: params[:room_code])
    @player = Player.where(id: params[:player_id]).first

    @player&.update(connected: true)
    broadcast_presence(true) if @player

    stream_from "millionaire_room_#{@room.code}"
  end

  def unsubscribed
    return unless @player

    @player.update(connected: false)
    broadcast_presence(false)
  end

  def broadcast_presence(is_online)
    ActionCable.server.broadcast("millionaire_room_#{@room.code}", {
      action:    "player_presence",
      player_id: @player.id.to_s,
      connected: is_online
    })
  end

  def start_game_loop
    @stop_loop   = false
    @room        = Room.find_by(code: params[:room_code])
    total_rounds = @room.game_state["total_rounds"].to_i
    total_rounds = 5 if total_rounds < 1

    Thread.new do
      total_rounds.times do |index|
        break if @stop_loop

        @room.reload

        # Broadcast the question that is already loaded (setup_game! loaded round 1;
        # next_round! at end of previous iteration loads subsequent rounds)
        ActionCable.server.broadcast("millionaire_room_#{@room.code}", {
          action:  "send_question",
          round:   index + 1,
          total:   total_rounds,
          text:    @room.game_state["question"],
          options: @room.game_state["answers"]
        })

        sleep_time = @room.game_state["time_per_round"].to_i
        sleep_time = 10 if sleep_time < 1
        sleep sleep_time

        # Score this round and load the next question
        GameServices::HowWantBeBillionare.new(@room).next_round!
      end

      unless @stop_loop
        @room.reload
        @room.update!(status: "finished")

        user_points = @room.game_state["user_points"] || {}
        nicknames   = @room.players.each_with_object({}) { |p, h| h[p.id.to_s] = p.nickname }

        # Sort leaderboard by points descending
        sorted = user_points.sort_by { |_, pts| -pts.to_i }.to_h

        ActionCable.server.broadcast("millionaire_room_#{@room.code}", {
          action:      "show_leaderboard",
          leaderboard: sorted,
          nicknames:   nicknames
        })
      end
    rescue => e
      Rails.logger.error("[MillionaireChannel] game loop crashed in room #{@room&.code}: #{e.message}\n#{e.backtrace.first(3).join("\n")}")
      @room&.update!(status: "finished") rescue nil
    end
  end

  def submit_millionaire_answer(data)
    return unless @player

    choice = data["choice"].to_i
    return unless (0..3).cover?(choice)

    @room.reload
    return unless @room.game_state["question_id"]

    GameServices::HowWantBeBillionare.new(@room).add_answer(@player.id, choice)
  end
end
