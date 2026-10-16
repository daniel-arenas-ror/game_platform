module GameServices
  # Werewolf-style Halloween game. Every phone gets a secret role: ghosts (who know each other) scare
  # one player out of the house each night, the Medium checks whether one player is a ghost, and the
  # trick-or-treaters hide in a room (a decoy, so every phone is busy at night). By day everyone
  # talks it over and votes someone out. Trick-or-treaters win when every ghost is out; ghosts win
  # when they're as many as everyone else still in the house.
  #
  # Phases: night → morning → discussion → vote → verdict → night … → game_over.
  # This class holds the rules; Games::HauntedHouseChannel runs the clock.
  class HauntedHouse < Base
    GHOST    = "ghost".freeze
    MEDIUM   = "medium".freeze
    GUEST    = "guest".freeze # a trick-or-treater
    ROLES    = [ GHOST, MEDIUM, GUEST ].freeze

    DISCUSSION_TIMES   = [ 60, 120, 180 ].freeze
    DEFAULT_DISCUSSION = 120
    GHOST_CHOICES      = %w[auto 1 2].freeze

    # Where trick-or-treaters hide at night. The morning tells where the victim was found.
    HIDING_PLACES = %w[attic basement kitchen library bedroom garden].freeze

    # Never sent to the TV or to other phones while the game is on.
    SECRET_KEYS = %w[roles ghost_picks medium_checks hides votes].freeze
    # The loop's own bookkeeping, of no use to any screen.
    INTERNAL_KEYS = %w[loop_id loop_beat skip].freeze

    attr_reader :room

    def initialize(room)
      @room    = room
      @players = room.players.to_a
    end

    # Reads the settings, deals the roles and starts at night 0 (the channel starts night 1).
    def setup_game!
      state  = @room.game_state
      ids    = @players.map { |p| p.id.to_s }
      medium = state["medium"].to_s != "false"
      ghosts = self.class.ghost_count(ids.size, state["ghosts"])

      @room.update!(
        status: "playing",
        game_state: state.except(*SECRET_KEYS, "winner", "out", "verdict", "victim").merge(
          "phase"           => "waiting",
          "night"           => 0,
          "discussion_time" => self.class.discussion_time(state["discussion_time"]),
          "ghosts"          => GHOST_CHOICES.include?(state["ghosts"].to_s) ? state["ghosts"].to_s : "auto",
          "medium"          => medium,
          "reveal_roles"    => state["reveal_roles"].to_s != "false",
          "roles"           => self.class.deal(ids, ghosts, medium),
          "ghost_total"     => ghosts,
          "alive"           => ids.shuffle,
          "out"             => [],
          "ghost_picks"     => {},
          "medium_checks"   => {},
          "hides"           => {},
          "votes"           => {},
          "victim"          => nil,
          "verdict"         => nil,
          "winner"          => nil,
          "phase_ends_at"   => nil,
          "skip"            => nil,
          "loop_id"         => nil,
          "loop_beat"       => nil
        )
      )

      broadcast_start
      true
    end

    # ── Settings ─────────────────────────────────────────────────────────────

    # Ghosts are always fewer than everyone else (else they'd win at once): "auto" is 1 ghost with up
    # to 7 players and 2 from 8, and a fixed choice is lowered when the room is too small for it.
    def self.ghost_count(players, choice)
      wanted = %w[1 2].include?(choice.to_s) ? choice.to_i : (players >= 8 ? 2 : 1)
      wanted.clamp(1, [ (players - 1) / 2, 1 ].max)
    end

    def self.discussion_time(value)
      DISCUSSION_TIMES.include?(value.to_i) ? value.to_i : DEFAULT_DISCUSSION
    end

    # { player_id => role }. The Medium needs at least 4 players, so there's someone left to check.
    def self.deal(ids, ghosts, medium)
      shuffled = ids.shuffle
      roles    = {}
      shuffled.shift(ghosts).each { |id| roles[id] = GHOST }
      roles[shuffled.shift] = MEDIUM if medium && ids.size >= 4 && shuffled.any?
      shuffled.each { |id| roles[id] = GUEST }
      roles
    end

    # ── Phases ───────────────────────────────────────────────────────────────

    # Before the first night: every phone shows its secret role.
    def start_roles!(duration)
      start_phase!("roles", duration)
    end

    # Seconds left in the current phase (nil when it has no timer).
    def seconds_left
      ends_at = @room.game_state["phase_ends_at"]
      ends_at && [ (ends_at - Time.now.to_f).ceil, 0 ].max
    end

    # The host's Skip: ends the discussion early. Only the discussion can be skipped.
    def skip!
      apply({ "_id" => @room.id, "game_state.phase" => "discussion" }, "$set" => { "game_state.skip" => "discussion" })
    end

    def skipped?(phase)
      fresh_state["skip"] == phase
    end

    # ── Night ────────────────────────────────────────────────────────────────

    def start_night!(duration)
      @room.reload
      start_phase!("night", duration,
                   "game_state.night"         => @room.game_state["night"].to_i + 1,
                   "game_state.ghost_picks"   => {},
                   "game_state.hides"         => {},
                   "game_state.victim"        => nil,
                   "game_state.verdict"       => nil)
    end

    # A ghost picks who to scare out. Ghosts may change their pick until the night ends, so they can
    # agree on one victim. Returns true when it counted.
    def ghost_pick!(player_id, target_id)
      pid, target = player_id.to_s, target_id.to_s
      state = fresh_state
      return false unless state["phase"] == "night" && living?(state, pid) && state["roles"][pid] == GHOST
      return false unless living?(state, target) && state["roles"][target] != GHOST

      apply(night_filter(state), "$set" => { "game_state.ghost_picks.#{pid}" => target })
    end

    # The Medium checks one player a night and learns at once whether they're a ghost.
    # Returns { ghost: true/false }, or nil when the check can't be made (one per night).
    def medium_check!(player_id, target_id)
      pid, target = player_id.to_s, target_id.to_s
      state = fresh_state
      night = state["night"].to_s
      return nil unless state["phase"] == "night" && living?(state, pid) && state["roles"][pid] == MEDIUM
      return nil unless living?(state, target) && target != pid

      ghost  = state["roles"][target] == GHOST
      filter = night_filter(state).merge("game_state.medium_checks.#{night}" => { "$exists" => false })
      return nil unless apply(filter, "$set" => { "game_state.medium_checks.#{night}" => { "target" => target, "ghost" => ghost } })

      { ghost: ghost }
    end

    # A trick-or-treater hides somewhere. Only the first choice of the night counts.
    def hide!(player_id, place)
      pid   = player_id.to_s
      state = fresh_state
      return false unless state["phase"] == "night" && living?(state, pid) && state["roles"][pid] == GUEST
      return false unless HIDING_PLACES.include?(place.to_s)

      filter = night_filter(state).merge("game_state.hides.#{pid}" => { "$exists" => false })
      apply(filter, "$set" => { "game_state.hides.#{pid}" => place.to_s })
    end

    # True when every player still in the house has done their night action and, with two ghosts,
    # they agree on one victim (until then the night runs on, so they have time to agree).
    def night_done?
      state  = fresh_state
      ghosts = state["alive"].to_a.select { |pid| state["roles"].to_h[pid] == GHOST }
      state["alive"].to_a.all? { |pid| acted_tonight?(state, pid) } &&
        ghosts.map { |pid| state["ghost_picks"].to_h[pid] }.uniq.size <= 1
    end

    # Players who have acted tonight. Safe to show anyone: every role acts at night.
    def acted_tonight
      state = fresh_state
      state["alive"].to_a.select { |pid| acted_tonight?(state, pid) }
    end

    # Scares out the ghosts' victim. Ghosts who disagree leave it to chance between their picks; no
    # pick at all and nobody is scared. Returns { victim:, place:, role:, winner: }.
    def end_night!
      @room.reload
      state  = @room.game_state
      picks  = state["ghost_picks"].to_h.select { |ghost, target| living?(state, ghost) && living?(state, target) }
      victim = most_picked(picks.values).sample

      fields = { "game_state.phase" => "morning", "game_state.phase_ends_at" => nil }
      place  = state["hides"].to_h[victim]
      if victim
        out = { "id" => victim, "night" => state["night"], "how" => "scared", "role" => state["roles"][victim] }
        fields["game_state.alive"]  = state["alive"] - [ victim ]
        fields["game_state.out"]    = state["out"].to_a + [ out ]
        fields["game_state.victim"] = { "id" => victim, "place" => place }
      end
      @room.atomic_set(fields)
      winner = settle_winner!

      { victim: victim, place: place, role: (state["roles"][victim] if victim && reveal_roles?), winner: winner }
    end

    # ── Day ──────────────────────────────────────────────────────────────────

    def start_discussion!(duration = nil)
      start_phase!("discussion", duration || @room.game_state["discussion_time"])
    end

    def start_vote!(duration)
      start_phase!("vote", duration, "game_state.votes" => {})
    end

    # One vote per player still in the house, for someone else still in it. The first vote counts.
    def vote!(player_id, target_id)
      pid, target = player_id.to_s, target_id.to_s
      state = fresh_state
      return false unless state["phase"] == "vote" && living?(state, pid) && living?(state, target) && pid != target

      filter = { "_id" => @room.id, "game_state.phase" => "vote", "game_state.night" => state["night"],
                 "game_state.votes.#{pid}" => { "$exists" => false } }
      apply(filter, "$set" => { "game_state.votes.#{pid}" => target })
    end

    def voted
      state = fresh_state
      state["votes"].to_h.keys & state["alive"].to_a
    end

    def all_voted?
      state = fresh_state
      state["alive"].to_a.all? { |pid| state["votes"].to_h.key?(pid) }
    end

    # The most votes is out of the house; a tie, or no votes, and nobody is.
    # Returns { out:, role:, votes: { voter => target }, tally:, winner: }.
    def end_vote!
      @room.reload
      state = @room.game_state
      votes = state["votes"].to_h.select { |voter, target| living?(state, voter) && living?(state, target) }
      tally = votes.values.tally
      top   = most_picked(votes.values)
      out   = top.first if top.one?

      fields = { "game_state.phase" => "verdict", "game_state.phase_ends_at" => nil,
                 "game_state.verdict" => { "out" => out, "votes" => votes, "tally" => tally } }
      if out
        entry = { "id" => out, "night" => state["night"], "how" => "voted", "role" => state["roles"][out] }
        fields["game_state.alive"] = state["alive"] - [ out ]
        fields["game_state.out"]   = state["out"].to_a + [ entry ]
      end
      @room.atomic_set(fields)
      winner = settle_winner!

      { out: out, role: (state["roles"][out] if out && reveal_roles?), votes: votes, tally: tally, winner: winner }
    end

    # ── The end ──────────────────────────────────────────────────────────────

    # "ghosts", "guests" or nil while the game goes on.
    def self.winner(roles, alive)
      ghosts = alive.count { |pid| roles[pid] == GHOST }
      return "guests" if ghosts.zero?
      return "ghosts" if ghosts >= alive.size - ghosts

      nil
    end

    def winner
      fresh_state["winner"]
    end

    # Player ids on the winning team (for the celebration), also counting players already out.
    def winners
      winners_in(fresh_state)
    end

    def finish_game!
      @room.reload
      @room.update!(status: "finished", game_state: @room.game_state.merge("phase" => "game_over", "phase_ends_at" => nil))
    end

    # ── Players leaving ──────────────────────────────────────────────────────

    # PlayerRemover has already dropped the player's role and picks. They leave the house; if that
    # settles the game (the last ghost left), the loop sees the winner and ends it.
    def player_removed!(player_id)
      pid = player_id.to_s
      Room.collection.update_one({ "_id" => @room.id }, { "$pull" => { "game_state.alive" => pid } })
      @room.reload
      return unless %w[night morning discussion vote verdict].include?(@room.game_state["phase"])

      out = @room.game_state["out"].to_a + [ { "id" => pid, "night" => @room.game_state["night"], "how" => "left", "role" => nil } ]
      @room.atomic_set("game_state.out" => out)
      settle_winner!
    end

    # ── What each screen may see ─────────────────────────────────────────────

    # The TV and everyone's phone: no roles (except of players who are out, when the room shows
    # them, and everyone's at game over), no picks, and the votes only once they're counted.
    def public_state
      state = @room.game_state
      over  = state["phase"] == "game_over" || state["winner"].present?
      shown = state.except(*SECRET_KEYS, *INTERNAL_KEYS)
      shown["out"] = state["out"].to_a.map { |o| over || state["reveal_roles"] ? o : o.merge("role" => nil) }
      shown["acted"] = acted_tonight if state["phase"] == "night"
      shown["acted"] = voted if state["phase"] == "vote"
      shown["roles"] = state["roles"] if over
      shown["winners"] = winners_in(state) if over
      shown["seconds_left"] = seconds_left
      shown
    end

    def host_state = public_state

    # A phone also sees its own role and what it did. A ghost sees the other ghosts and their picks;
    # the Medium sees every check they've made.
    def player_state(player_id)
      pid   = player_id.to_s
      state = @room.game_state
      role  = state["roles"].to_h[pid]
      shown = public_state.merge("my_role" => role, "alive_me" => state["alive"].to_a.include?(pid))

      case role
      when GHOST
        shown["ghost_team"]  = state["roles"].select { |_, r| r == GHOST }.keys
        shown["ghost_picks"] = state["ghost_picks"].to_h
      when MEDIUM
        shown["medium_checks"] = state["medium_checks"].to_h
      when GUEST
        shown["my_hide"] = state["hides"].to_h[pid]
      end
      shown["my_vote"] = state["votes"].to_h[pid] if state["phase"] == "vote"
      shown
    end

    private

    def winners_in(state)
      return [] unless state["winner"]

      state["roles"].to_h.select { |_, role| (role == GHOST) == (state["winner"] == "ghosts") }.keys
    end

    # The ids picked most often (several on a tie, none when nobody picked).
    def most_picked(ids)
      tally = ids.tally
      top   = tally.values.max
      tally.select { |_, n| n == top }.keys
    end

    def start_phase!(phase, duration, fields = {})
      ends_at = duration && Time.now.to_f + duration.to_i
      @room.atomic_set({ "game_state.phase" => phase, "game_state.phase_ends_at" => ends_at, "game_state.skip" => nil }.merge(fields))
      @room.game_state
    end

    def settle_winner!
      @room.reload
      state  = @room.game_state
      winner = self.class.winner(state["roles"].to_h, state["alive"].to_a)
      @room.atomic_set("game_state.winner" => winner) if winner && state["winner"].nil?
      winner
    end

    def acted_tonight?(state, pid)
      case state["roles"].to_h[pid]
      when GHOST  then state["ghost_picks"].to_h.key?(pid)
      when MEDIUM then state["medium_checks"].to_h.key?(state["night"].to_s)
      when GUEST  then state["hides"].to_h.key?(pid)
      else true # a player whose role was dropped (left the room) holds nobody up
      end
    end

    def reveal_roles?
      @room.game_state["reveal_roles"] != false
    end

    def living?(state, pid)
      state["alive"].to_a.include?(pid)
    end

    def night_filter(state)
      { "_id" => @room.id, "game_state.phase" => "night", "game_state.night" => state["night"] }
    end

    def fresh_state
      Room.where(_id: @room.id).only(:game_state).first&.game_state || {}
    end

    def apply(filter, update)
      Room.collection.update_one(filter, update).modified_count == 1
    end
  end
end
