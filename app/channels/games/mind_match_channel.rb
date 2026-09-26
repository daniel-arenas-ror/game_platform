class Games::MindMatchChannel < ApplicationCable::Channel
  STREAM_PREFIX       = "mind_match_room_"
  REVEAL_DURATION     = 8   # seconds the per-player answers are shown
  TRANSITION_DURATION = 3   # seconds the "round X — get ready" screen shows

  def subscribed
    @room   = Room.find_by(code: params[:room_code])
    @player = Player.find_by(id: params[:player_id]) if params[:player_id].present?

    @player&.update(connected: true)

    stream_from "#{STREAM_PREFIX}#{@room.code}"

    transmit({
      action: "state_snapshot",
      state:  @room.game_state.merge(
        "nicknames"     => nicknames_map,
        "total_players" => @room.players.count
      )
    })
  end

  def unsubscribed
    return unless @player

    @player.update(connected: false)
    broadcast({ action: "player_presence", player_id: @player.id.to_s, connected: false })
  end

  # ── Host actions ──────────────────────────────────────────────────────────

  def start_game_loop(data)
    return unless host?

    # Guard: don't start a second loop if one is already running
    @room.reload
    return if @room.game_state["loop_running"]

    @stop_loop = false
    @room      = Room.find_by(code: params[:room_code])

    @room.atomic_set("game_state.loop_running" => true)

    svc            = GameServices::MindMatch.new(@room)
    total_rounds   = @room.game_state["total_rounds"].to_i
    time_per_round = @room.game_state["time_per_round"].to_i

    Thread.new do
      total_rounds.times do |i|
        break if @stop_loop
        round = i + 1

        # ── 0. Transition screen between rounds (skipped before round 1) ──
        if i > 0
          broadcast({
            action:       "next_round",
            round:        round,
            total_rounds: total_rounds
          })
          sleep TRANSITION_DURATION
          break if @stop_loop
        end

        # ── 1. Pick a category and broadcast it ───────────────────────────
        category = svc.pick_category!
        @room.atomic_set("game_state.round" => round, "game_state.status" => "collecting")

        broadcast({
          action:        "show_category",
          category:      category,
          round:         round,
          total_rounds:  total_rounds,
          duration:      time_per_round,
          total_players: @room.players.count,
          nicknames:     nicknames_map
        })

        sleep time_per_round
        sleep 1.5   # grace period for in-flight submissions
        break if @stop_loop

        # ── 2. Score and reveal ───────────────────────────────────────────
        @room.atomic_set("game_state.status" => "revealing")
        result = svc.score_round!

        broadcast({
          action:       "reveal",
          round:        round,
          total_rounds: total_rounds,
          category:     category,
          groups:       result[:groups],
          answers:      result[:answers],
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
          game_state: @room.game_state.merge(
            "status"       => "game_over",
            "loop_running" => false
          )
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
      @room&.update!(status: "finished", game_state: @room.game_state.merge("loop_running" => false)) rescue nil
    end
  end

  def restart_game(data)
    return unless host?

    @stop_loop = true
    @room = Room.find_by(code: params[:room_code])
    @room.atomic_set("game_state.loop_running" => false)
    GameServices::MindMatch.new(@room).setup_game!
    broadcast({ action: "game_restarted" })
  end

  # ── Player actions ────────────────────────────────────────────────────────

  def submit_word(data)
    return unless @player

    word = data["word"].to_s.strip
    return if word.empty?
    return unless GameServices::MindMatch.new(@room).add_answer(@player.id, word)

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
