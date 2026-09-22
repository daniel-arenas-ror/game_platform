class Games::MindMatchChannel < ApplicationCable::Channel
  STREAM_PREFIX   = "mind_match_room_"
  REVEAL_DURATION = 6   # seconds the grouped results are shown before the next round

  def subscribed
    @room   = Room.find_by(code: params[:room_code])
    @player = Player.find_by(id: params[:player_id]) if params[:player_id].present?

    @player&.update(connected: true)

    stream_from "#{STREAM_PREFIX}#{@room.code}"

    transmit({ action: "state_snapshot", state: @room.game_state })
  end

  def unsubscribed
    return unless @player

    @player.update(connected: false)
    broadcast({ action: "player_presence", player_id: @player.id.to_s, connected: false })
  end

  # ── Host actions ──────────────────────────────────────────────────────────

  # Called by the host controller once the ActionCable connection is established.
  def start_game_loop(data)
    return unless host?

    @stop_loop   = false
    @room        = Room.find_by(code: params[:room_code])
    svc          = GameServices::MindMatch.new(@room)
    total_rounds = @room.game_state["total_rounds"].to_i
    time_per_round = @room.game_state["time_per_round"].to_i

    Thread.new do
      total_rounds.times do |i|
        break if @stop_loop
        round = i + 1

        # ── 1. Pick a category and broadcast it ──────────────────────────
        category = svc.pick_category!
        @room.set("game_state.round" => round, "game_state.status" => "collecting")

        broadcast({
          action:       "show_category",
          category:     category,
          round:        round,
          total_rounds: total_rounds,
          duration:     time_per_round
        })

        sleep time_per_round
        sleep 1.5   # grace period for in-flight submissions
        break if @stop_loop

        # ── 2. Score and reveal ───────────────────────────────────────────
        @room.set("game_state.status" => "revealing")
        result = svc.score_round!

        broadcast({
          action:       "reveal",
          round:        round,
          total_rounds: total_rounds,
          category:     category,
          groups:       result[:groups],
          round_scores: result[:round_scores],
          scores:       result[:scores],
          nicknames:    nicknames_map
        })

        sleep REVEAL_DURATION
      end

      # ── 3. Game over ──────────────────────────────────────────────────
      unless @stop_loop
        @room.reload
        @room.update!(
          status:     "finished",
          game_state: @room.game_state.merge("status" => "game_over")
        )
        broadcast({
          action:    "game_over",
          scores:    @room.game_state["scores"],
          nicknames: nicknames_map
        })
      end
    rescue => e
      Rails.logger.error("[MindMatchChannel] loop crashed in room #{@room&.code}: #{e.message}\n#{e.backtrace.first(3).join("\n")}")
      broadcast({ action: "game_error" }) rescue nil
      @room&.update!(status: "finished") rescue nil
    end
  end

  def restart_game(data)
    return unless host?

    @stop_loop = true
    @room = Room.find_by(code: params[:room_code])
    GameServices::MindMatch.new(@room).setup_game!
    broadcast({ action: "game_restarted" })
  end

  # ── Player actions ────────────────────────────────────────────────────────

  def submit_word(data)
    return unless @player

    @room.reload
    return unless @room.game_state["status"] == "collecting"

    word = data["word"].to_s.strip
    return if word.empty?

    GameServices::MindMatch.new(@room).add_answer(@player.id, word)

    broadcast({
      action:    "player_submitted",
      player_id: @player.id.to_s,
      nickname:  @player.nickname
    })
  end

  private

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
