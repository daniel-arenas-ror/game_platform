class Games::MillionaireChannel < ApplicationCable::Channel
  REVEAL_DURATION = 3   # seconds the reveal is shown before the next question

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
    stream       = "millionaire_room_#{@room.code}"

    Thread.new do
      total_rounds.times do |index|
        break if @stop_loop

        @room.reload
        sleep_time = @room.game_state["time_per_round"].to_i
        sleep_time = 10 if sleep_time < 1

        # ── 1. Broadcast the current question ────────────────────────────
        ActionCable.server.broadcast(stream, {
          action:  "send_question",
          round:   index + 1,
          total:   total_rounds,
          text:    @room.game_state["question"],
          options: @room.game_state["answers"]
        })

        sleep sleep_time
        break if @stop_loop

        # ── 2. Score the round ────────────────────────────────────────────
        svc      = GameServices::HowWantBeBillionare.new(@room)
        result   = svc.score_round!
        @room.reload
        nicknames = @room.players.each_with_object({}) { |p, h| h[p.id.to_s] = p.nickname }

        ActionCable.server.broadcast(stream, {
          action:                 "reveal_answer",
          round:                  index + 1,
          total:                  total_rounds,
          question:               @room.game_state["question"],
          options:                @room.game_state["answers"],
          correct_answer_indices: result[:correct_answer_indices],
          round_scores:           result[:round_scores],
          user_points:            result[:user_points],
          question_points:        result[:question_points],
          nicknames:              nicknames
        })

        sleep REVEAL_DURATION
        break if @stop_loop

        # ── 3. Load next question (skip on final round) ───────────────────
        svc.advance_question! if index < total_rounds - 1
      end

      unless @stop_loop
        @room.reload
        @room.update!(status: "finished")

        user_points = @room.game_state["user_points"] || {}
        nicknames   = @room.players.each_with_object({}) { |p, h| h[p.id.to_s] = p.nickname }
        sorted      = user_points.sort_by { |_, pts| -pts.to_i }.to_h

        ActionCable.server.broadcast(stream, {
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
