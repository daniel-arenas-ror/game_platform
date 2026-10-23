module GameServices
  # Hidden-character search. Each round a new scene is filled with a crowd of code-drawn people; the
  # TV and the phones show who to find, and everyone searches the same scene on their phone
  # (zooming in). The first three to tap the target score 3, 2 and 1 points and the round ends.
  # A wrong tap freezes that phone for a few seconds, so tapping everyone doesn't pay.
  #
  # Phases: waiting → intro → search → reveal (each round) → game_over.
  # This class holds the rules; Games::CharacterHuntChannel runs the clock.
  class CharacterHunt < Base
    DIFFICULTIES = {
      "easy"   => { count: 60,  decoys: 0, size: 1.15 },
      "normal" => { count: 100, decoys: 2, size: 1.0 },
      "hard"   => { count: 150, decoys: 4, size: 0.85 }
    }.freeze
    DEFAULT_DIFFICULTY = "normal".freeze
    ROUND_CHOICES      = [ 3, 5, 8 ].freeze
    DEFAULT_ROUNDS     = 5
    ROUND_TIMES        = [ 60, 90, 120 ].freeze
    DEFAULT_ROUND_TIME = 90

    # Points for the 1st, 2nd and 3rd to find the target. The round ends with the last of them
    # (or when every player still in the room has found it).
    POINTS         = [ 3, 2, 1 ].freeze
    FREEZE_SECONDS = 3

    attr_reader :room
    # Set by the channel's game loop: its phase changes then only land while it's still the room's
    # loop, so a loop that Play Again replaced can't overwrite the new game.
    attr_accessor :loop_id

    def initialize(room)
      @room    = room
      @players = room.players.to_a
    end

    def setup_game!
      state  = @room.game_state
      ids    = @players.map { |p| p.id.to_s }
      rounds = self.class.pick(state["total_rounds"], ROUND_CHOICES, DEFAULT_ROUNDS)

      @room.update!(
        status: "playing",
        game_state: state.except("scene", "target", "target_index", "finders", "frozen", "winners").merge(
          "phase"             => "waiting",
          "round"             => 0,
          "total_rounds"      => rounds,
          "round_time"        => self.class.pick(state["round_time"], ROUND_TIMES, DEFAULT_ROUND_TIME),
          "difficulty"        => DIFFICULTIES.key?(state["difficulty"]) ? state["difficulty"] : DEFAULT_DIFFICULTY,
          "scene_order"       => self.class.scene_order(rounds),
          "scene"             => nil,
          "target"            => nil,
          "target_index"      => nil,
          "finders"           => [],
          "frozen"            => {},
          "wrong"             => ids.to_h { |id| [ id, 0 ] },
          "scores"            => ids.to_h { |id| [ id, 0 ] },
          "winners"           => nil,
          "phase_ends_at"     => nil,
          "search_started_at" => nil,
          "skip"              => nil,
          "loop_id"           => nil,
          "loop_beat"         => nil
        )
      )

      broadcast_start
      true
    end

    def self.pick(value, choices, default)
      choices.include?(value.to_i) ? value.to_i : default
    end

    # One scene per round, every scene before any repeats, never the same twice in a row.
    def self.scene_order(rounds)
      scenes = Crowd::SCENES.keys
      order  = []
      order += (scenes.shuffle.then { |s| s.first == order.last ? s.rotate : s }) while order.size < rounds
      order.first(rounds)
    end

    # ── Rounds ───────────────────────────────────────────────────────────────

    # Builds round `round`'s crowd (1-based) and shows who to find.
    def start_round!(round, duration)
      settings = DIFFICULTIES.fetch(@room.game_state["difficulty"])
      crowd    = Crowd.build(@room.game_state["scene_order"][round - 1], **settings)
      target   = crowd["scene"]["characters"][crowd["target_index"]]

      start_phase!("intro", duration,
                   "game_state.round" => round, "game_state.scene" => crowd["scene"],
                   "game_state.target" => target["traits"], "game_state.target_index" => crowd["target_index"],
                   "game_state.finders" => [], "game_state.frozen" => {})
    end

    def start_search!
      start_phase!("search", @room.game_state["round_time"], "game_state.search_started_at" => Time.now.to_f)
    end

    # A phone taps the scene at x, y (fractions of it). Returns { "result" => … }:
    #   found   — the target: "place" (1–3), "points", "time" (seconds into the search)
    #   wrong   — someone else ("index"); the phone is frozen "until" (epoch seconds)
    #   miss    — nobody there (no penalty: zooming fingers slip)
    #   frozen  — still frozen from a wrong tap
    #   already — this player found the target already
    #   closed  — not searching, or the round is full
    def tap!(player_id, x, y)
      pid   = player_id.to_s
      x     = Float(x, exception: false)
      y     = Float(y, exception: false)
      state = fresh_state
      return { "result" => "closed" } unless state["phase"] == "search" && x && y && state["scores"].to_h.key?(pid)
      return { "result" => "already" } if state["finders"].to_a.any? { |f| f["id"] == pid }

      now = Time.now.to_f
      return { "result" => "frozen", "until" => state["frozen"][pid] } if state["frozen"].to_h[pid].to_f > now

      index = Crowd.hit(state["scene"], x, y)
      return { "result" => "miss" } unless index
      return wrong!(pid, index, state["round"], now) unless index == state["target_index"]

      found!(pid, state, now)
    end

    # Enough players have found the target: the first three, or everyone still here if fewer.
    def round_over?
      state = fresh_state
      found = state["finders"].to_a.map { |f| f["id"] }
      found.size >= POINTS.size || (present_ids(state) - found).empty?
    end

    def end_round!(duration)
      start_phase!("reveal", duration)
    end

    def last_round?
      @room.game_state["round"].to_i >= @room.game_state["total_rounds"].to_i
    end

    def finish_game!
      @room.reload
      scores  = @room.game_state["scores"].to_h
      best    = scores.values.max.to_i
      winners = best.positive? ? scores.select { |_, s| s == best }.keys : []
      @room.update!(status: "finished",
                    game_state: @room.game_state.merge("phase" => "game_over", "phase_ends_at" => nil, "winners" => winners))
      winners
    end

    # The host's Skip: ends the reveal early.
    def skip!
      apply({ "_id" => @room.id, "game_state.phase" => "reveal" }, "$set" => { "game_state.skip" => true })
    end

    def skipped?
      fresh_state["skip"] == true
    end

    def seconds_left
      ends_at = @room.game_state["phase_ends_at"]
      ends_at && [ (ends_at - Time.now.to_f).ceil, 0 ].max
    end

    # ── What each screen may see ─────────────────────────────────────────────

    INTERNAL_KEYS = %w[loop_id loop_beat scene_order frozen skip].freeze

    # Everything but where the target stands, until the reveal.
    def public_state
      state = @room.game_state
      shown = state.except(*INTERNAL_KEYS)
      shown.delete("target_index") unless %w[reveal game_over].include?(state["phase"])
      shown["seconds_left"] = seconds_left
      shown
    end

    def host_state = public_state

    def player_state(player_id)
      public_state.merge("frozen_until" => @room.game_state["frozen"].to_h[player_id.to_s])
    end

    private

    def wrong!(pid, index, round, now)
      frozen_until = now + FREEZE_SECONDS
      apply({ "_id" => @room.id, "game_state.phase" => "search", "game_state.round" => round },
            "$set" => { "game_state.frozen.#{pid}" => frozen_until }, "$inc" => { "game_state.wrong.#{pid}" => 1 })
      { "result" => "wrong", "index" => index, "until" => frozen_until }
    end

    # Only the first three count, even when taps arrive at the same moment.
    def found!(pid, state, now)
      time  = (now - state["search_started_at"].to_f).round(1)
      added = apply({ "_id" => @room.id, "game_state.phase" => "search", "game_state.round" => state["round"],
                      "game_state.finders.id" => { "$ne" => pid }, "game_state.finders.#{POINTS.size - 1}" => { "$exists" => false } },
                    "$push" => { "game_state.finders" => { "id" => pid, "time" => time } })
      return { "result" => "closed" } unless added

      place  = fresh_state["finders"].index { |f| f["id"] == pid }
      points = POINTS[place]
      apply({ "_id" => @room.id }, "$set" => { "game_state.finders.#{place}.points" => points },
                                   "$inc" => { "game_state.scores.#{pid}" => points })
      @room.reload
      { "result" => "found", "place" => place + 1, "points" => points, "time" => time }
    end

    # Players still in the room (a player who left holds nobody up).
    def present_ids(state)
      state["scores"].to_h.keys & Player.where(room_id: @room.id).pluck(:id).map(&:to_s)
    end

    def start_phase!(phase, duration, fields = {})
      ends_at = duration && Time.now.to_f + duration.to_i
      fields  = { "game_state.phase" => phase, "game_state.phase_ends_at" => ends_at, "game_state.skip" => nil }.merge(fields)
      if loop_id
        apply({ "_id" => @room.id, "game_state.loop_id" => loop_id }, "$set" => fields)
        @room.reload
      else
        @room.atomic_set(fields)
      end
      @room.game_state
    end

    def fresh_state
      Room.where(_id: @room.id).only(:game_state).first&.game_state || {}
    end

    def apply(filter, update)
      Room.collection.update_one(filter, update).modified_count == 1
    end
  end
end
