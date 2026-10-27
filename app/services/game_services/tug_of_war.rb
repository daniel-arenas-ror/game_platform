module GameServices
  # Team math race. The players are split into Red and Blue; every phone gets its own math problem
  # and each correct answer pulls the rope a little towards the player's team. A team wins the round
  # when the rope reaches its end (or is on its side when the time limit runs out). A wrong answer
  # freezes that phone for a moment, so guessing doesn't pay.
  #
  # The rope is one number, "position": −100 is Red's end, +100 Blue's. A pull moves it
  # 100 / (pulls_per_player × team size), so a smaller team pulls harder and 3 vs 4 is fair.
  #
  # Phases: teams (the host moves players between teams, then starts) → countdown → pulling →
  # round_over (each round) → game_over. This class holds the rules; Games::TugOfWarChannel runs
  # the clock.
  class TugOfWar < Base
    TEAMS        = %w[red blue].freeze
    DIRECTION    = { "red" => -1, "blue" => 1 }.freeze
    ROPE_END     = 100
    DIFFICULTIES = Problems::DIFFICULTIES
    DEFAULT_DIFFICULTY = "easy".freeze
    ANSWER_MODES = %w[type choice].freeze
    DEFAULT_ANSWER_MODE = "type".freeze
    # How many correct answers each player of a team needs (net of the other team's) to win.
    ROPE_LENGTHS = { "short" => 5, "normal" => 8, "long" => 12 }.freeze
    DEFAULT_ROPE_LENGTH = "normal".freeze
    TIME_LIMITS  = [ 0, 60, 120, 180 ].freeze # 0 = no limit
    DEFAULT_TIME_LIMIT = 120
    ROUND_CHOICES = [ 1, 3 ].freeze
    DEFAULT_ROUNDS = 1
    FREEZE_SECONDS = 2

    attr_reader :room
    # Set by the channel's game loop: its phase changes then only land while it's still the room's
    # loop, so a loop that Play Again replaced can't overwrite the new game.
    attr_accessor :loop_id

    def initialize(room)
      @room    = room
      @players = room.players.to_a
    end

    def setup_game!
      state = @room.game_state
      ids   = @players.map { |p| p.id.to_s }

      @room.update!(
        status: "playing",
        game_state: state.except("teams", "problems", "frozen", "pulls", "wrong", "winner", "champion", "winners").merge(
          "phase"         => "teams",
          "round"         => 0,
          "total_rounds"  => self.class.pick(state["total_rounds"], ROUND_CHOICES, DEFAULT_ROUNDS),
          "time_limit"    => self.class.pick(state["time_limit"], TIME_LIMITS, DEFAULT_TIME_LIMIT),
          "difficulty"    => DIFFICULTIES.include?(state["difficulty"]) ? state["difficulty"] : DEFAULT_DIFFICULTY,
          "answer_mode"   => ANSWER_MODES.include?(state["answer_mode"]) ? state["answer_mode"] : DEFAULT_ANSWER_MODE,
          "rope_length"   => ROPE_LENGTHS.key?(state["rope_length"]) ? state["rope_length"] : DEFAULT_ROPE_LENGTH,
          "teams"         => self.class.split(ids),
          "position"      => 0,
          "team_pulls"    => TEAMS.to_h { |t| [ t, 0 ] },
          "streak"        => nil,
          "wins"          => TEAMS.to_h { |t| [ t, 0 ] },
          "problems"      => {},
          "frozen"        => {},
          "pulls"         => ids.to_h { |id| [ id, 0 ] },
          "wrong"         => ids.to_h { |id| [ id, 0 ] },
          "winner"        => nil,
          "champion"      => nil,
          "winners"       => nil,
          "phase_ends_at" => nil,
          "start"         => nil,
          "skip"          => nil,
          "loop_id"       => nil,
          "loop_beat"     => nil
        )
      )

      broadcast_start
      true
    end

    def self.pick(value, choices, default)
      choices.include?(value.to_i) && value.to_s.strip.match?(/\A\d+\z/) ? value.to_i : default
    end

    # Random even teams: { player_id => "red" | "blue" }. With an odd count either team may get the extra.
    def self.split(ids)
      first, second = TEAMS.shuffle
      ids.shuffle.each_with_index.to_h { |id, i| [ id, i.even? ? first : second ] }
    end

    # ── Teams (before the first round) ───────────────────────────────────────

    # The host moves a player to the other team (or to `team`).
    def move_player!(player_id, team = nil)
      pid   = player_id.to_s
      state = fresh_state
      now   = state["teams"].to_h[pid]
      return false unless state["phase"] == "teams" && now

      team = TEAMS.include?(team) ? team : (TEAMS - [ now ]).first
      apply({ "_id" => @room.id, "game_state.phase" => "teams" }, "$set" => { "game_state.teams.#{pid}" => team }) &&
        @room.reload && true
    end

    def shuffle_teams!
      state = fresh_state
      return false unless state["phase"] == "teams"

      apply({ "_id" => @room.id, "game_state.phase" => "teams" },
            "$set" => { "game_state.teams" => self.class.split(state["teams"].to_h.keys) }) && @room.reload && true
    end

    # Both teams need someone on the rope.
    def teams_ready?(state = fresh_state)
      TEAMS.all? { |t| team_size(state, t).positive? }
    end

    # The host's Start pulling.
    def request_start!
      return false unless teams_ready?

      apply({ "_id" => @room.id, "game_state.phase" => "teams" }, "$set" => { "game_state.start" => true })
    end

    def start_requested?
      fresh_state["start"] == true
    end

    # A player who joins after the start goes to the smaller team (and gets a problem if a round is on).
    def join!(player_id)
      pid   = player_id.to_s
      state = fresh_state
      return state["teams"][pid] if state["teams"].to_h.key?(pid)
      return nil if %w[game_over].include?(state["phase"])

      team   = TEAMS.min_by { |t| [ team_size(state, t), rand ] }
      fields = { "game_state.teams.#{pid}" => team, "game_state.pulls.#{pid}" => 0, "game_state.wrong.#{pid}" => 0 }
      fields["game_state.problems.#{pid}"] = new_problem(state) if %w[countdown pulling].include?(state["phase"])
      apply({ "_id" => @room.id, "game_state.teams.#{pid}" => { "$exists" => false } }, "$set" => fields)
      @room.reload
      @room.game_state["teams"][pid]
    end

    # A team left with nobody gets a player from the other team, if it can spare one.
    def player_removed!(_player_id)
      state = fresh_state
      empty = TEAMS.find { |t| team_size(state, t).zero? }
      return unless empty && %w[teams countdown pulling round_over].include?(state["phase"])

      donor = state["teams"].to_h.select { |_, t| t != empty }.keys
      return if donor.size < 2

      apply({ "_id" => @room.id }, "$set" => { "game_state.teams.#{donor.sample}" => empty })
      @room.reload
    end

    # ── Rounds ───────────────────────────────────────────────────────────────

    # Round `round` (1-based): the rope back in the middle and a problem on every phone.
    def start_round!(round, duration)
      state    = fresh_state
      problems = state["teams"].to_h.keys.to_h { |pid| [ pid, new_problem(state) ] }
      start_phase!("countdown", duration,
                   "game_state.round" => round, "game_state.position" => 0, "game_state.winner" => nil,
                   "game_state.team_pulls" => TEAMS.to_h { |t| [ t, 0 ] }, "game_state.streak" => nil,
                   "game_state.problems" => problems, "game_state.frozen" => {}, "game_state.start" => nil)
    end

    def start_pulling!
      limit = fresh_state["time_limit"].to_i
      start_phase!("pulling", limit.positive? ? limit : nil)
    end

    # A phone answers its problem. Returns { "result" => … }:
    #   correct — the rope moved: "position", "team", "step", "pulls" (this player's), "team_pulls",
    #             "streak", "won" (the pull that ended the round), and the next "problem"
    #   wrong   — "answer" (the right one), frozen for "seconds", and the next "problem"
    #   frozen  — still frozen from a wrong answer, for "seconds" more
    #   stale   — not the problem this phone has now (answered twice); "problem" is the current one
    #   closed  — the rope isn't being pulled
    def answer!(player_id, problem_id, value)
      pid   = player_id.to_s
      state = fresh_state
      team  = state["teams"].to_h[pid]
      return { "result" => "closed" } unless state["phase"] == "pulling" && state["winner"].nil? && team

      problem = state["problems"].to_h[pid]
      return { "result" => "stale", "problem" => Problems.shown(problem) } unless problem && problem["id"] == problem_id.to_s

      now    = Time.now.to_f
      frozen = frozen_seconds(state, pid, now)
      return { "result" => "frozen", "seconds" => frozen } if frozen.positive?

      given = Integer(value.to_s.strip, exception: false)
      given == problem["answer"] ? pull!(pid, team, problem, state) : wrong!(pid, problem, state, now)
    end

    def round_won?
      fresh_state["winner"].present?
    end

    # The time limit ran out: the team the rope leans towards wins; dead centre is a draw.
    def time_up!
      position = fresh_state["position"].to_f
      winner   = position.zero? ? "draw" : (position.negative? ? "red" : "blue")
      apply({ "_id" => @room.id, "game_state.phase" => "pulling", "game_state.winner" => nil },
            "$set" => { "game_state.winner" => winner })
      @room.reload
    end

    def end_round!(duration)
      state  = fresh_state
      winner = state["winner"]
      fields = TEAMS.include?(winner) ? { "game_state.wins.#{winner}" => state["wins"].to_h[winner].to_i + 1 } : {}
      start_phase!("round_over", duration, fields)
    end

    # Over when a team has won most of the rounds, or every round is played.
    def last_round?
      state = fresh_state
      total = state["total_rounds"].to_i
      state["round"].to_i >= total || state["wins"].to_h.values.max.to_i > total / 2
    end

    # Returns the winning players' ids (the whole champion team; none on a draw).
    def finish_game!
      @room.reload
      wins     = @room.game_state["wins"].to_h
      best     = wins.values.max.to_i
      top      = wins.select { |_, w| w == best }.keys
      champion = top.size == 1 && best.positive? ? top.first : "draw"
      winners  = @room.game_state["teams"].to_h.select { |_, t| t == champion }.keys
      @room.update!(status: "finished",
                    game_state: @room.game_state.merge("phase" => "game_over", "phase_ends_at" => nil,
                                                       "champion" => champion, "winners" => winners))
      winners
    end

    # The player with the most pulls in the game (ties: all of them).
    def mvp_ids
      pulls = fresh_state["pulls"].to_h
      best  = pulls.values.max.to_i
      best.positive? ? pulls.select { |_, p| p == best }.keys : []
    end

    # The host's Skip: ends the round-over screen early.
    def skip!
      apply({ "_id" => @room.id, "game_state.phase" => "round_over" }, "$set" => { "game_state.skip" => true })
    end

    def skipped?
      fresh_state["skip"] == true
    end

    def seconds_left
      ends_at = @room.game_state["phase_ends_at"]
      ends_at && [ (ends_at - Time.now.to_f).ceil, 0 ].max
    end

    # ── What each screen may see ─────────────────────────────────────────────

    INTERNAL_KEYS = %w[loop_id loop_beat problems frozen start skip].freeze

    def public_state
      shown = @room.game_state.except(*INTERNAL_KEYS)
      shown["team_sizes"]   = TEAMS.to_h { |t| [ t, team_size(@room.game_state, t) ] }
      shown["seconds_left"] = seconds_left
      shown["mvp"]          = mvp_ids if shown["phase"] == "game_over"
      shown
    end

    def host_state = public_state

    # The phone's own problem (without the answer), and its freeze as seconds left: a phone's clock
    # may not match the server's.
    def player_state(player_id)
      pid = player_id.to_s
      public_state.merge("team"           => @room.game_state["teams"].to_h[pid],
                         "problem"        => Problems.shown(@room.game_state["problems"].to_h[pid]),
                         "frozen_seconds" => frozen_seconds(@room.game_state, pid, Time.now.to_f))
    end

    private

    # One atomic update: only this problem counts, only once, and only while the round is open.
    # The pull that takes the rope to its end also names the winner.
    def pull!(pid, team, problem, state)
      step = ROPE_END.to_f / (ROPE_LENGTHS.fetch(state["rope_length"]) * [ team_size(state, team), 1 ].max)
      step = (step * DIRECTION[team]).round(3)
      next_problem = new_problem(state, previous: problem["text"])
      doc = Room.collection.find_one_and_update(
        { "_id" => @room.id, "game_state.phase" => "pulling", "game_state.winner" => nil,
          "game_state.problems.#{pid}.id" => problem["id"] },
        { "$inc" => { "game_state.position" => step, "game_state.pulls.#{pid}" => 1, "game_state.team_pulls.#{team}" => 1 },
          "$set" => { "game_state.problems.#{pid}" => next_problem } },
        return_document: :after
      )
      return { "result" => "closed" } unless doc

      position = doc["game_state"]["position"].to_f
      won      = position.abs >= ROPE_END &&
                 apply({ "_id" => @room.id, "game_state.winner" => nil }, "$set" => { "game_state.winner" => team })
      streak   = bump_streak(doc["game_state"]["streak"], team)
      @room.reload

      { "result" => "correct", "team" => team, "step" => step,
        "position" => position.clamp(-ROPE_END, ROPE_END).round(2),
        "pulls" => doc["game_state"]["pulls"][pid], "team_pulls" => doc["game_state"]["team_pulls"],
        "streak" => streak, "won" => won, "problem" => Problems.shown(next_problem) }
    end

    def wrong!(pid, problem, state, now)
      next_problem = new_problem(state, previous: problem["text"])
      changed = apply({ "_id" => @room.id, "game_state.phase" => "pulling", "game_state.problems.#{pid}.id" => problem["id"] },
                      "$set" => { "game_state.frozen.#{pid}" => now + FREEZE_SECONDS, "game_state.problems.#{pid}" => next_problem },
                      "$inc" => { "game_state.wrong.#{pid}" => 1 })
      return { "result" => "closed" } unless changed

      { "result" => "wrong", "answer" => problem["answer"], "seconds" => FREEZE_SECONDS,
        "problem" => Problems.shown(next_problem) }
    end

    # Pulls in a row by the same team (just for show on the TV, so no lock).
    def bump_streak(streak, team)
      count  = streak.is_a?(Hash) && streak["team"] == team ? streak["count"].to_i + 1 : 1
      streak = { "team" => team, "count" => count }
      @room.atomic_set("game_state.streak" => streak)
      streak
    end

    def new_problem(state, previous: nil)
      Problems.generate(state["difficulty"], state["answer_mode"], previous: previous)
    end

    def team_size(state, team)
      state["teams"].to_h.values.count(team)
    end

    def frozen_seconds(state, pid, now)
      [ state["frozen"].to_h[pid].to_f - now, 0 ].max.round(1)
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
