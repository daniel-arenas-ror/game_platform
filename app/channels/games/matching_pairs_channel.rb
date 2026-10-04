class Games::MatchingPairsChannel < ApplicationCable::Channel
  STREAM_PREFIX = "matching_pairs_room_"
  START_DELAY   = 3    # seconds before the first memorize phase
  ROUND_PAUSE   = 5    # seconds the round results stay up before the next board
  GRACE_PERIOD  = 1    # extra time after the round timer for in-flight flips
  POLL_INTERVAL = 0.25 # how often a round checks whether everyone has cleared their board

  def subscribed
    @room   = Room.find_by(code: params[:room_code])
    @player = find_player
    return if subscription_rejected?

    track_player_subscribed(@player)

    stream_from "#{STREAM_PREFIX}#{@room.code}"
    # Only the host gets the card layout to show during the memorize phase.
    stream_from host_stream if host?

    svc = service
    transmit({
      action:    "state_snapshot",
      state:     host? ? svc.host_state : svc.public_state,
      board:     (svc.player_board(@player.id) if @player),
      nicknames: nicknames_map
    })
  end

  def unsubscribed
    return unless @player

    track_player_unsubscribed(@player)
    broadcast({ action: "player_presence", player_id: @player.id.to_s, connected: false })
  end

  # ── Host actions ──────────────────────────────────────────────────────────

  def start_game_loop(_data)
    return unless host?

    # Guard: only one loop per game, even if the host page reloads
    claimed = Room.collection.update_one(
      { "code" => params[:room_code], "status" => "playing", "game_state.loop_running" => { "$ne" => true } },
      { "$set" => { "game_state.loop_running" => true } }
    )
    return unless claimed.modified_count == 1

    # A restart replaces @loop_id, which stops a loop that is still sleeping
    loop_id = @loop_id = SecureRandom.hex(4)
    @room   = Room.find_by(code: params[:room_code])
    svc     = GameServices::MatchingPairs.new(@room)

    Thread.new do
      sleep START_DELAY
      total_rounds = @room.game_state["total_rounds"].to_i

      total_rounds.times do |i|
        break if loop_id != @loop_id
        round = i + 1
        deck  = svc.start_round!(round)
        state = @room.game_state

        round_info = {
          round:        round,
          total_rounds: total_rounds,
          cols:         state["cols"],
          rows:         state["rows"],
          duration:     state["memorize_time"]
        }
        broadcast({ action: "memorize", **round_info })
        ActionCable.server.broadcast(host_stream, { action: "memorize_board", **round_info, deck: deck })

        sleep state["memorize_time"].to_i
        break if loop_id != @loop_id

        svc.begin_play!
        broadcast({
          action:        "play",
          round:         round,
          duration:      @room.game_state["round_time"],
          round_ends_at: @room.game_state["round_ends_at"]
        })

        wait_for_round(@room.game_state["round_time"].to_i, svc, loop_id)
        break if loop_id != @loop_id

        svc.end_round!
        broadcast({
          action:       "round_over",
          round:        round,
          total_rounds: total_rounds,
          deck:         @room.game_state["deck"],
          scores:       @room.game_state["scores"],
          progress:     svc.progress,
          nicknames:    nicknames_map
        })

        sleep ROUND_PAUSE if round < total_rounds
      end

      if loop_id == @loop_id
        svc.finish_game!
        broadcast({
          action:    "game_over",
          scores:    @room.game_state["scores"],
          nicknames: nicknames_map
        })
      end
    rescue => e
      Rails.logger.error("[MatchingPairsChannel] game loop crashed in room #{@room&.code}: #{e.message}\n#{e.backtrace.first(3).join("\n")}")
      broadcast({ action: "game_error" }) rescue nil
      @room&.update!(status: "finished") rescue nil
    end
  end

  def restart_game(_data)
    return unless host?

    @loop_id = nil
    @room = Room.find_by(code: params[:room_code])
    GameServices::MatchingPairs.new(@room).setup_game!
    broadcast({ action: "game_restarted" })
  end

  # ── Player actions ────────────────────────────────────────────────────────

  # data["index"] is the card position (row-major) the player tapped.
  def flip(data)
    return unless @player

    result = service.flip!(@player.id, data["index"])

    unless result[:ok]
      transmit({ action: "flip_rejected", index: data["index"] })
      return
    end

    transmit({ action: "flip_result", **result.except(:ok) })
    return if result[:result] == "open"

    broadcast({
      action:    "progress",
      player_id: @player.id.to_s,
      score:     result[:score],
      matches:   result[:matches],
      cleared:   result[:cleared],
      match:     result[:result] == "match"
    })
  end

  private

  # Sleeps until the round timer (plus grace) runs out or every player has cleared their board.
  def wait_for_round(seconds, svc, loop_id)
    deadline = monotonic_now + seconds + GRACE_PERIOD

    while monotonic_now < deadline
      return if loop_id != @loop_id
      return if svc.all_cleared?

      sleep POLL_INTERVAL
    end
  end

  def monotonic_now
    Process.clock_gettime(Process::CLOCK_MONOTONIC)
  end

  def service
    GameServices::MatchingPairs.new(@room)
  end

  def host?
    @player.nil?
  end

  def host_stream
    "#{STREAM_PREFIX}#{@room.code}_host"
  end

  def broadcast(payload)
    ActionCable.server.broadcast("#{STREAM_PREFIX}#{@room.code}", payload)
  end

  def nicknames_map
    @room.players.each_with_object({}) { |p, h| h[p.id.to_s] = p.nickname }
  end
end
