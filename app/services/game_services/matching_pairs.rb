module GameServices
  class MatchingPairs < Base
    # "cols x rows" => seconds the host shows the face-up board before the round starts.
    GRIDS = {
      "4x4" => { "cols" => 4, "rows" => 4, "memorize" => 8 },
      "4x5" => { "cols" => 4, "rows" => 5, "memorize" => 10 },
      "5x6" => { "cols" => 5, "rows" => 6, "memorize" => 15 },
      "6x6" => { "cols" => 6, "rows" => 6, "memorize" => 20 }
    }.freeze
    ROUND_TIMES   = [ 60, 90, 120, 180 ].freeze
    ROUND_CHOICES = [ 1, 2, 3, 5 ].freeze
    CATEGORIES    = (Catalog::CATEGORIES + [ "random" ]).freeze

    MATCH_POINTS  = 100
    WRONG_PENALTY = 10 # per wrong pair; a score never drops below 0

    def initialize(room)
      @room    = room
      @players = room.players.to_a
    end

    def setup_game!
      grid         = GRIDS.key?(@room.game_state["grid"]) ? @room.game_state["grid"] : "4x5"
      round_time   = (@room.game_state["round_time"] || 120).to_i
      round_time   = 120 unless ROUND_TIMES.include?(round_time)
      total_rounds = (@room.game_state["total_rounds"] || 1).to_i
      total_rounds = 1 unless ROUND_CHOICES.include?(total_rounds)
      category     = CATEGORIES.include?(@room.game_state["category"]) ? @room.game_state["category"] : "random"

      @room.update!(
        status: "playing",
        game_state: @room.game_state.except("deck", "boards", "round_ends_at").merge(
          "status"         => "waiting",
          "loop_running"   => false,
          "round"          => 0,
          "total_rounds"   => total_rounds,
          "grid"           => grid,
          "cols"           => GRIDS[grid]["cols"],
          "rows"           => GRIDS[grid]["rows"],
          "memorize_time"  => GRIDS[grid]["memorize"],
          "round_time"     => round_time,
          "category"       => category,
          "scores"         => @players.to_h { |p| [ p.id.to_s, 0 ] }
        )
      )

      broadcast_start
      true
    end

    # Deals a fresh shuffled board, gives every player an empty board and starts the memorize phase.
    # The same layout is used by everyone, since they all memorize it from the host screen.
    def start_round!(round)
      @room.reload
      @players = @room.players.to_a
      state = @room.game_state
      pairs = state["cols"].to_i * state["rows"].to_i / 2
      cards = Catalog.sample(state["category"], pairs)
      deck  = (cards + cards).shuffle

      @room.atomic_set(
        "game_state.round"            => round,
        "game_state.status"           => "memorize",
        "game_state.deck"             => deck,
        "game_state.boards"           => @players.to_h { |p| [ p.id.to_s, empty_board ] },
        "game_state.scores"           => @players.to_h { |p| [ p.id.to_s, 0 ] }.merge(state["scores"] || {}),
        "game_state.memorize_ends_at" => Time.now.to_f + state["memorize_time"].to_i,
        "game_state.round_ends_at"    => nil
      )
      deck
    end

    # Ends the memorize phase. round_ends_at (epoch seconds) lets a reloaded page resume the countdown.
    def begin_play!
      @room.atomic_set(
        "game_state.status"        => "playing",
        "game_state.round_ends_at" => Time.now.to_f + @room.game_state["round_time"].to_i
      )
    end

    def end_round!
      @room.atomic_set("game_state.status" => "round_over")
    end

    def finish_game!
      @room.reload
      @room.update!(status: "finished", game_state: @room.game_state.merge("status" => "game_over", "loop_running" => false))
    end

    # A player turns card `index` face up. The first card of a pair stays open; the second one
    # scores a match (both stay open) or a miss (both flip back on the phone).
    # Returns { ok: false } or { ok: true, result: "open" | "match" | "miss", index:, item:, … }.
    def flip!(player_id, index)
      @room.reload
      state = @room.game_state
      pid   = player_id.to_s
      board = state.dig("boards", pid)
      deck  = state["deck"]
      index = Integer(index, exception: false)

      return { ok: false } unless state["status"] == "playing" && board && deck
      return { ok: false } unless index&.between?(0, deck.length - 1)
      return { ok: false } if board["matched"].include?(index) || board["open"] == index

      path   = "game_state.boards.#{pid}"
      open   = board["open"]
      # Matching on the player's current open card serializes their flips: a double tap or two
      # flips arriving at once can't both apply.
      filter = { "_id" => @room.id, "game_state.status" => "playing", "game_state.round" => state["round"], "#{path}.open" => open }

      if open.nil?
        return { ok: false } unless apply(filter, "$set" => { "#{path}.open" => index })

        return { ok: true, result: "open", index: index, item: deck[index] }
      end

      score   = state.dig("scores", pid).to_i
      match   = deck[open]["key"] == deck[index]["key"]
      matches = board["matches"].to_i + (match ? 1 : 0)

      update =
        if match
          score += MATCH_POINTS
          { "$push" => { "#{path}.matched" => { "$each" => [ open, index ] } }, "$inc" => { "#{path}.matches" => 1 } }
        else
          score = [ score - WRONG_PENALTY, 0 ].max
          { "$inc" => { "#{path}.wrong" => 1 } }
        end
      update["$set"] = { "#{path}.open" => nil, "game_state.scores.#{pid}" => score }
      return { ok: false } unless apply(filter, update)

      {
        ok:      true,
        result:  match ? "match" : "miss",
        index:   index,
        item:    deck[index],
        other:   open,
        score:   score,
        matches: matches,
        cleared: matches * 2 == deck.length
      }
    end

    # True once every player still in the round has found all the pairs.
    def all_cleared?
      state = Room.where(_id: @room.id).only(:game_state).first&.game_state || {}
      pairs = state["deck"].to_a.length / 2
      state["boards"].to_h.values.all? { |b| b["matches"].to_i >= pairs }
    end

    # Per-player progress for the host leaderboard: { pid => { "matches", "wrong" } }.
    def progress
      @room.game_state["boards"].to_h.transform_values { |b| b.slice("matches", "wrong") }
    end

    # What everyone may see: no card layout while a round is being played.
    def public_state
      state = @room.game_state.except("deck", "boards", "loop_running")
      state["pairs"]    = state["cols"].to_i * state["rows"].to_i / 2
      state["progress"] = progress
      state["preload"]  = preload_urls if %w[memorize playing].include?(state["status"])
      state["deck"]     = @room.game_state["deck"] if %w[round_over game_over].include?(state["status"])
      state
    end

    # The round's images, without positions, so phones can load them while the host shows the board.
    def preload_urls
      @room.game_state["deck"].to_a.filter_map { |card| card["src"] }.uniq.shuffle
    end

    # The host sees the layout during the memorize phase (and after the round).
    def host_state
      state = public_state
      state["deck"] = @room.game_state["deck"] if state["status"] == "memorize"
      state
    end

    # A player's own board: the pairs found so far and the card currently open.
    def player_board(player_id)
      board = @room.game_state.dig("boards", player_id.to_s)
      deck  = @room.game_state["deck"]
      return nil unless board && deck

      open = board["open"]
      {
        "matched" => board["matched"].to_h { |i| [ i, deck[i] ] },
        "open"    => open && { "index" => open, "item" => deck[open] },
        "matches" => board["matches"].to_i,
        "wrong"   => board["wrong"].to_i
      }
    end

    private

    def empty_board
      { "matched" => [], "open" => nil, "matches" => 0, "wrong" => 0 }
    end

    def apply(filter, update)
      Room.collection.update_one(filter, update).modified_count == 1
    end
  end
end
