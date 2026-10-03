class Games::SoupOfNumbersChannel < ApplicationCable::Channel
  STREAM_PREFIX  = "soup_of_numbers_room_"
  START_DELAY    = 3    # seconds before round 1, so everyone sees the soup first
  RESULT_PAUSE   = 4    # seconds the found (or missed) number is shown before the next round
  GRACE_PERIOD   = 1    # extra time after the round timer for in-flight claims
  POLL_INTERVAL  = 0.25 # how often the round checks whether someone found the number

  def subscribed
    @room   = Room.find_by(code: params[:room_code])
    @player = find_player
    return if subscription_rejected?

    track_player_subscribed(@player)

    stream_from "#{STREAM_PREFIX}#{@room.code}"

    transmit({ action: "state_snapshot", state: service.public_state, nicknames: nicknames_map })
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
    loop_id  = @loop_id = SecureRandom.hex(4)
    @room      = Room.find_by(code: params[:room_code])
    svc        = GameServices::SoupOfNumbers.new(@room)

    Thread.new do
      sleep START_DELAY

      @room.game_state["total_rounds"].to_i.times do |i|
        break if loop_id != @loop_id
        round  = i + 1
        target = svc.start_round!(round)

        broadcast({
          action:       "new_round",
          round:        round,
          total_rounds: @room.game_state["total_rounds"],
          duration:     @room.game_state["round_time"],
          target:       svc.public_target
        })

        found = wait_for_winner(@room.game_state["round_time"].to_i, loop_id)
        break if loop_id != @loop_id

        unless found
          entry = svc.miss_round!
          broadcast({ action: "number_missed", round: round, number: target["number"], cells: entry["cells"] }) if entry
        end

        sleep RESULT_PAUSE
      end

      if loop_id == @loop_id
        @room.reload
        @room.update!(status: "finished", game_state: @room.game_state.merge("status" => "game_over", "loop_running" => false))
        broadcast({
          action:    "game_over",
          scores:    @room.game_state["scores"],
          colors:    @room.game_state["colors"],
          nicknames: nicknames_map
        })
      end
    rescue => e
      Rails.logger.error("[SoupOfNumbersChannel] game loop crashed in room #{@room&.code}: #{e.message}\n#{e.backtrace.first(3).join("\n")}")
      broadcast({ action: "game_error" }) rescue nil
      @room&.update!(status: "finished") rescue nil
    end
  end

  def restart_game(_data)
    return unless host?

    @loop_id = nil
    @room = Room.find_by(code: params[:room_code])
    GameServices::SoupOfNumbers.new(@room).setup_game!
    broadcast({ action: "game_restarted" })
  end

  # ── Player actions ────────────────────────────────────────────────────────

  # data["cells"] is an Array of [row, col] the player selected, in tap order.
  def claim_number(data)
    return unless @player

    result = service.claim!(@player.id, data["cells"])

    unless result[:ok]
      transmit({ action: "claim_rejected" })
      return
    end

    broadcast({
      action:    "number_found",
      round:     result[:entry]["round"],
      number:    result[:entry]["number"],
      cells:     result[:entry]["cells"],
      player_id: @player.id.to_s,
      nickname:  @player.nickname,
      color:     @room.game_state.dig("colors", @player.id.to_s),
      points:    result[:points],
      scores:    @room.game_state["scores"]
    })
  end

  private

  # Sleeps until a player claims the number or the round timer (plus grace) runs out.
  # Returns true when someone found it.
  def wait_for_winner(seconds, loop_id)
    deadline = monotonic_now + seconds + GRACE_PERIOD

    while monotonic_now < deadline
      return false if loop_id != @loop_id

      state = Room.where(code: @room.code).only(:game_state).first&.game_state || {}
      return true if state["round_winner"]

      sleep POLL_INTERVAL
    end

    false
  end

  def monotonic_now
    Process.clock_gettime(Process::CLOCK_MONOTONIC)
  end

  def service
    GameServices::SoupOfNumbers.new(@room)
  end

  def host?
    @player.nil?
  end

  def broadcast(payload)
    ActionCable.server.broadcast("#{STREAM_PREFIX}#{@room.code}", payload)
  end

  def nicknames_map
    @room.players.each_with_object({}) { |p, h| h[p.id.to_s] = p.nickname }
  end
end
