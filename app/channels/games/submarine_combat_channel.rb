class Games::SubmarineCombatChannel < ApplicationCable::Channel
  STREAM_PREFIX    = "submarine_combat_room_"
  ROUND_DURATION   = 20   # seconds players have to pick a coordinate
  REVEAL_DURATION  = 4    # seconds the round result is shown

  def subscribed
    @room   = Room.find_by(code: params[:room_code])
    @player = Player.find_by(id: params[:player_id]) if params[:player_id].present?

    @player&.update(connected: true)

    stream_from "#{STREAM_PREFIX}#{@room.code}"

    nicknames = @room.players.each_with_object({}) { |p, h| h[p.id.to_s] = p.nickname }
    transmit({ action: "state_snapshot", state: @room.game_state, nicknames: nicknames })
  end

  def unsubscribed
    return unless @player

    @player.update(connected: false)
    broadcast({
      action:    "player_presence",
      player_id: @player.id.to_s,
      connected: false
    })
  end

  # ── Placement phase ───────────────────────────────────────────────────────

  # Player requests a new random fleet (shuffle button).
  def shuffle_placement(data)
    return unless @player

    @room.reload
    grid_size = @room.game_state["grid_size"].to_i
    sub_count = @room.game_state["sub_count"].to_i
    new_ships = GameServices::SubmarineCombat.new(@room).generate_placement(grid_size, sub_count)

    @room.set("game_state.placements.#{@player.id}.ships"     => new_ships)
    @room.set("game_state.placements.#{@player.id}.confirmed" => false)

    transmit({ action: "placement_shuffled", ships: new_ships })
  end

  # Player saves a manually-adjusted fleet and marks themselves confirmed.
  def confirm_placement(data)
    return unless @player

    ships = data["ships"]
    return unless ships.is_a?(Array)

    @room.reload
    grid_size = @room.game_state["grid_size"].to_i

    # Basic server-side sanity: all cells within bounds, no duplicates
    all_cells = ships.flat_map { |s| s["cells"] }
    valid = all_cells.all? { |c| c.is_a?(Array) && c.length == 2 &&
                                 c[0].between?(0, grid_size - 1) &&
                                 c[1].between?(0, grid_size - 1) }
    return unless valid && all_cells.uniq.length == all_cells.length

    @room.set(
      "game_state.placements.#{@player.id}.ships"     => ships,
      "game_state.placements.#{@player.id}.confirmed" => true
    )

    @room.reload
    all_confirmed = @room.game_state["placements"].values.all? { |p| p["confirmed"] }
    nicknames     = @room.players.each_with_object({}) { |p, h| h[p.id.to_s] = p.nickname }

    broadcast({
      action:        "placement_confirmed",
      player_id:     @player.id.to_s,
      all_confirmed: all_confirmed,
      nicknames:     nicknames,
      confirmed_ids: @room.game_state["placements"].select { |_, p| p["confirmed"] }.keys
    })
  end

  # ── Battle phase ──────────────────────────────────────────────────────────

  # Host triggers this after all players have confirmed placement.
  def start_battle_loop(data)
    return unless host?

    @stop_loop = false
    @room      = Room.find_by(code: params[:room_code])
    stream     = "#{STREAM_PREFIX}#{@room.code}"

    @room.set("game_state.phase" => "battle")

    Thread.new do
      loop do
        break if @stop_loop

        @room.reload
        round = @room.game_state["round"].to_i + 1
        @room.set("game_state.round" => round)

        active_ids = active_player_ids
        break if active_ids.empty?

        nicknames = @room.players.each_with_object({}) { |p, h| h[p.id.to_s] = p.nickname }

        # ── 1. Start round ────────────────────────────────────────────────
        broadcast({
          action:     "start_round",
          round:      round,
          duration:   ROUND_DURATION,
          active_ids: active_ids,
          nicknames:  nicknames
        })

        sleep ROUND_DURATION
        break if @stop_loop

        # ── 2. Resolve picks ──────────────────────────────────────────────
        @room.reload
        round_picks = @room.game_state["round_picks"] || {}

        svc    = GameServices::SubmarineCombat.new(@room)
        result = svc.resolve_round!(round_picks)

        @room.reload
        nicknames = @room.players.each_with_object({}) { |p, h| h[p.id.to_s] = p.nickname }

        broadcast({
          action:     "round_result",
          round:      round,
          picks:      round_picks,
          hits:       result[:hits],
          sunk_ships: result[:sunk_ships],
          eliminated: result[:eliminated],
          scores:     result[:scores],
          placements: safe_placements,
          nicknames:  nicknames,
          winner:     result[:winner]
        })

        if result[:winner]
          @room.reload
          @room.update!(status: "finished")
          @room.set("game_state.phase" => "game_over")
          broadcast({
            action:    "game_over",
            winner_id: result[:winner],
            scores:    result[:scores],
            nicknames: nicknames
          })
          break
        end

        sleep REVEAL_DURATION
        break if @stop_loop
      end
    rescue => e
      Rails.logger.error("[SubmarineCombatChannel] game loop crashed in room #{@room&.code}: #{e.message}\n#{e.backtrace.first(3).join("\n")}")
      broadcast({ action: "game_error" }) rescue nil
      @room&.update!(status: "finished") rescue nil
    end
  end

  # Player (or spectator) submits their shot for the current round.
  def submit_shot(data)
    return unless @player

    row = data["row"].to_i
    col = data["col"].to_i

    @room.reload
    grid_size = @room.game_state["grid_size"].to_i
    return unless row.between?(0, grid_size - 1) && col.between?(0, grid_size - 1)
    return if @room.game_state["round_picks"][@player.id.to_s]   # already picked

    @room.set("game_state.round_picks.#{@player.id}" => [row, col])

    broadcast({
      action:    "shot_submitted",
      player_id: @player.id.to_s
    })
  end

  # Host "Play Again" — resets to placement phase with new auto-placements.
  def restart_game(data)
    return unless host?

    @stop_loop = true
    @room      = Room.find_by(code: params[:room_code])
    GameServices::SubmarineCombat.new(@room).setup_game!
    broadcast({ action: "game_restarted" })
  end

  private

  def host?
    @player.nil?
  end

  def broadcast(payload)
    ActionCable.server.broadcast("#{STREAM_PREFIX}#{@room.code}", payload)
  end

  def active_player_ids
    (@room.game_state["placements"] || {})
      .reject { |_, p| p["eliminated"] }
      .keys
  end

  # Returns placements with ship cell positions but strips hit detail
  # that would let clients cheat — hits are fine to share (everyone sees them).
  def safe_placements
    @room.game_state["placements"] || {}
  end

  def nicknames_map
    @room.players.each_with_object({}) { |p, h| h[p.id.to_s] = p.nickname }
  end
end
