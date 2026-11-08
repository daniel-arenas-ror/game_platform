class Games::MillionaireChannel < ApplicationCable::Channel
  REVEAL_DURATION = 7    # "auto" mode: seconds the reveal is shown (answer counts, answer, standings)
  ANSWER_POLL     = 0.25 # how often the loop checks whether everyone has answered
  ALL_IN_PAUSE    = 0.6  # once everyone answered: a beat before the reveal, so it doesn't feel cut off
  BET_SECONDS     = 10   # time to place a bet before the final question
  MANUAL_WAIT_LIMIT = 1.minutes # "manual" mode: give up if the host never taps Next

  def subscribed
    @room   = Room.find_by(code: params[:room_code])
    @player = find_player
    return if subscription_rejected?

    track_player_subscribed(@player)
    broadcast_presence(true) if @player

    stream_from "millionaire_room_#{@room.code}"
    transmit_current_screen if @player
  end

  def unsubscribed
    @stop_loop = true # the host left or reloaded: this loop ends (a reload starts a new one)
    return unless @player

    track_player_unsubscribed(@player)
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
    @next_signal = Queue.new
    @room        = Room.find_by(code: params[:room_code])
    manual       = @room.game_state["advance"] == "manual"
    total_rounds = GameServices::HowWantBeBillionare.new(@room).total_rounds
    stream       = "millionaire_room_#{@room.code}"

    Thread.new do
      total_rounds.times do |index|
        break if @stop_loop

        @room.reload
        sleep_time = @room.game_state["time_per_round"].to_i
        sleep_time = GameServices::HowWantBeBillionare::DEFAULT_SECONDS if sleep_time < 1
        svc        = GameServices::HowWantBeBillionare.new(@room)

        # ── 0. Bets before the final question ────────────────────────────
        if svc.final_round?(index) && svc.bets_open?
          broadcast_screen(stream, {
            action:    "place_bets",
            round:     index + 1,
            total:     total_rounds,
            points:    @room.game_state["user_points"] || {},
            fractions: GameServices::HowWantBeBillionare::BET_FRACTIONS,
            duration:  BET_SECONDS
          }, BET_SECONDS)
          wait_until(BET_SECONDS) { svc.everyone_bet? }
          break if @stop_loop
          @room.reload
        end

        # ── 1. Broadcast the current question ────────────────────────────
        svc.start_question!(sleep_time)
        broadcast_screen(stream, {
          action:   "send_question",
          round:    index + 1,
          total:    total_rounds,
          text:     @room.game_state["question"],
          options:  @room.game_state["answers"],
          points:   svc.question_points(index),
          final:    svc.final_round?(index),
          duration: sleep_time
        }, sleep_time)

        wait_until(sleep_time) { svc.everyone_answered? }
        break if @stop_loop

        # ── 2. Score the round ────────────────────────────────────────────
        result   = svc.score_round!(index)
        @room.reload
        nicknames = @room.players.each_with_object({}) { |p, h| h[p.id.to_s] = p.nickname }

        broadcast_screen(stream, {
          action:                 "reveal_answer",
          round:                  index + 1,
          total:                  total_rounds,
          question:               @room.game_state["question"],
          options:                @room.game_state["answers"],
          correct_answer_indices: result[:correct_answer_indices],
          answer_counts:          result[:answer_counts],
          previous_points:        result[:previous_points],
          new_leader:             result[:new_leader],
          round_scores:           result[:round_scores],
          round_details:          result[:round_details],
          streaks:                result[:streaks],
          user_points:            result[:user_points],
          question_points:        result[:question_points],
          nicknames:              nicknames,
          advance:                manual ? "manual" : "auto",
          next_in:                (REVEAL_DURATION unless manual),
          last:                   index == total_rounds - 1
        }, (manual ? nil : REVEAL_DURATION))

        manual ? wait_for_next : sleep(REVEAL_DURATION)
        break if @stop_loop

        # ── 3. Load next question (skip on final round) ───────────────────
        svc.advance_question!(index + 1) if index < total_rounds - 1
      end

      unless @stop_loop
        @room.reload
        @room.update!(status: "finished")
        @room.atomic_set("game_state.screen" => nil)

        user_points = @room.game_state["user_points"] || {}
        nicknames   = @room.players.each_with_object({}) { |p, h| h[p.id.to_s] = p.nickname }
        sorted      = user_points.sort_by { |_, pts| -pts.to_i }.to_h

        ActionCable.server.broadcast(stream, {
          action:      "show_leaderboard",
          leaderboard: sorted,
          nicknames:   nicknames,
          awards:      GameServices::HowWantBeBillionare.new(@room).awards
        })
      end
    rescue => e
      Rails.logger.error("[MillionaireChannel] game loop crashed in room #{@room&.code}: #{e.message}\n#{e.backtrace.first(3).join("\n")}")
      @room&.update!(status: "finished") rescue nil
    end
  end

  # Host only: reset scores with the same settings. Everyone reloads, and the host's page
  # starts a fresh game loop when it reconnects.
  def restart_game(_data = {})
    return if @player

    @stop_loop = true
    @room = Room.find_by(code: params[:room_code])
    GameServices::HowWantBeBillionare.new(@room).setup_game!(keep_asked_questions: true)
    ActionCable.server.broadcast("millionaire_room_#{@room.code}", { action: "game_restarted" })
  end

  # Host only, "manual" mode: go on to the next question (or the results after the last one).
  def next_question(_data = {})
    return if @player

    @next_signal&.push(true)
  end

  def submit_millionaire_answer(data)
    return unless @player

    choice = data["choice"].to_i
    return unless (0..3).cover?(choice)

    @room.reload
    return unless @room.game_state["question_id"]

    GameServices::HowWantBeBillionare.new(@room).add_answer(@player.id, choice)
  end

  # Final question bet: a share of the player's points (0, 0.25, 0.5 or 1), only while bets are open.
  def place_bet(data)
    return unless @player

    @room.reload
    return unless @room.game_state.dig("screen", "action") == "place_bets"

    svc    = GameServices::HowWantBeBillionare.new(@room)
    amount = svc.place_bet!(@player.id, data["fraction"])
    return unless amount

    transmit({ action: "bet_placed", amount: amount })
    ActionCable.server.broadcast("millionaire_room_#{@room.code}", { action: "bets_progress", placed: svc.bets_placed })
  end

  # 50:50 on this player's phone: only they are told which answers to take away.
  def use_fifty(_data = {})
    return unless @player

    @room.reload
    return unless @room.game_state.dig("screen", "action") == "send_question"

    removed = GameServices::HowWantBeBillionare.new(@room).use_fifty!(@player.id)
    transmit({ action: "fifty_fifty", removed: removed }) if removed
  end

  private

  # Every question and reveal is also saved as the room's current screen, so a phone that connects
  # late (the TV starts the game while phones are still loading the page) or reconnects still gets it.
  def broadcast_screen(stream, payload, seconds)
    ends_at = seconds && Time.current.to_f + seconds
    @room.atomic_set("game_state.screen" => payload.merge(ends_at: ends_at).as_json)
    ActionCable.server.broadcast(stream, payload)
  end

  # Sends a subscribing player the screen everyone else is on, with the time that's left.
  def transmit_current_screen
    screen = @room.game_state["screen"]
    return unless @room.status == "playing" && screen.is_a?(Hash)

    ends_at = screen.delete("ends_at")
    left    = ends_at && (ends_at - Time.current.to_f).floor
    case screen["action"]
    when "send_question"
      return unless left && left.positive?

      screen["duration"] = left
      screen["my_choice"] = @room.game_state.dig("answers_history", @room.game_state["question_id"].to_s, @player.id.to_s)
      screen["fifty_used"]    = @room.game_state.dig("fifty", @player.id.to_s).present?
      screen["fifty_removed"] = GameServices::HowWantBeBillionare.new(@room).fifty_removed(@player.id)
    when "place_bets"
      return unless left && left.positive?

      screen["duration"] = left
      screen["my_bet"]   = @room.game_state.dig("bets", @player.id.to_s)
    when "reveal_answer"
      screen["next_in"] = left.clamp(0..) if left
    end
    transmit(screen)
  end

  # Waits out the time, or less: once everyone is in (all answers, all bets) the game goes on
  # right away instead of everyone staring at the clock.
  def wait_until(seconds)
    deadline = Time.current.to_f + seconds
    while Time.current.to_f < deadline
      return if @stop_loop
      return sleep(ALL_IN_PAUSE) if yield

      sleep ANSWER_POLL
    end
  end

  # Blocks the game loop until the host taps Next. Wakes up every second so a restart or the host
  # leaving (@stop_loop) ends the loop instead of leaving the thread waiting forever.
  def wait_for_next
    @next_signal.clear
    deadline = MANUAL_WAIT_LIMIT.from_now
    until @stop_loop || Time.current > deadline
      return if @next_signal.pop(timeout: 1)
    end
    @stop_loop = true
  end
end
