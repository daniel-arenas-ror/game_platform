module GameServices
  # Exquisite-corpse drawing game for Halloween. Three drawing rounds: everyone draws a head, then
  # the monsters move along and everyone draws a body for someone else's monster, seeing only a
  # strip at the bottom of the head, then the legs the same way. The TV reveals each monster, the
  # phones vote for their favourite (not the one they started), and every vote scores a point for
  # each artist of that monster.
  #
  # Phases: waiting → drawing (×3) → reveal → vote → results → game_over.
  # This class holds the rules; Games::MonsterMashChannel runs the clock.
  class MonsterMash < Base
    PARTS       = %w[head body legs].freeze
    DRAW_TIMES  = [ 45, 60, 90 ].freeze
    DEFAULT_DRAW_TIME = 60
    # Share of the canvas height, at the bottom of the previous part, the next artist sees.
    GUIDE_STRIP = 0.15

    MAX_STROKES       = 400  # per drawing
    MAX_STROKE_POINTS = 1000 # per stroke

    WORDS = YAML.load_file(Rails.root.join("config/monster_mash/words.yml")).freeze

    attr_reader :room

    def initialize(room)
      @room    = room
      @players = room.players.to_a
    end

    def setup_game!
      state   = @room.game_state
      ids     = @players.map { |p| p.id.to_s }.shuffle
      game_id = SecureRandom.hex(6)
      words   = self.class.words(@room.locale)

      ::MonsterMash::Drawing.where(room_id: @room.id).delete_all
      @room.update!(
        status: "playing",
        game_state: state.except("votes", "results", "done", "reveal_index").merge(
          "game_id"       => game_id,
          "phase"         => "waiting",
          "round"         => -1,
          "draw_time"     => self.class.draw_time(state["draw_time"]),
          "theme"         => words["themes"].sample,
          "order"         => ids,
          "monsters"      => self.class.names(words, ids.size).each_with_index.map { |name, i|
            { "name" => name, "starter" => ids[i], "artists" => {} }
          },
          "done"          => {},
          "votes"         => {},
          "results"       => nil,
          "reveal_index"  => nil,
          "scores"        => ids.to_h { |id| [ id, 0 ] },
          "phase_ends_at" => nil,
          "skip"          => nil,
          "loop_id"       => nil,
          "loop_beat"     => nil
        )
      )

      broadcast_start
      true
    end

    def self.draw_time(value)
      DRAW_TIMES.include?(value.to_i) ? value.to_i : DEFAULT_DRAW_TIME
    end

    def self.words(locale)
      WORDS.fetch(locale.to_s, WORDS["en"])
    end

    # `count` different funny names: "Sir Wobblefang of the Swamp", "Doña Babitas del Pantano".
    # (There are tens of thousands of combinations for at most 12 monsters.)
    def self.names(words, count)
      n     = words["names"]
      names = Set.new
      names << "#{n['titles'].sample} #{n['first'].sample}#{n['second'].sample} #{n['places'].sample}" while names.size < count
      names.to_a
    end

    # Which monster the player at `position` draws in `round`. Each round the monsters move one
    # place along, so with 3+ players nobody draws twice on the same monster.
    def self.monster_for(position, round, count)
      (position - round) % count
    end

    # ── Drawing rounds ───────────────────────────────────────────────────────

    # The theme intro before the first round, and the short "pass it on" pause between rounds.
    def start_interlude!(phase, duration)
      start_phase!(phase, duration)
    end

    # Starts round `round` (0 head, 1 body, 2 legs): one drawing per player, on their monster.
    def start_round!(round, duration)
      @room.reload
      state = @room.game_state
      order = state["order"].to_a
      part  = PARTS.fetch(round)

      monsters = state["monsters"].map(&:dup)
      order.each_with_index do |pid, position|
        index = self.class.monster_for(position, round, order.size)
        monsters[index] = monsters[index].merge("artists" => monsters[index]["artists"].merge(part => pid))
        ::MonsterMash::Drawing.find_or_create_by!(room_id: @room.id, game_id: state["game_id"], monster: index, part: part) do |d|
          d.player_id = pid
        end
      end

      start_phase!("drawing", duration, "game_state.round" => round, "game_state.done" => {}, "game_state.monsters" => monsters)
    end

    # What the player draws this round: the monster, the part, and the strip at the bottom of the
    # part above it (nil for heads). nil when the player isn't drawing.
    def assignment(player_id)
      state   = @room.game_state
      drawing = current_drawing(player_id, state)
      return nil unless drawing

      above = PARTS.index(drawing.part) - 1
      guide = if above >= 0
        prev = ::MonsterMash::Drawing.where(room_id: @room.id, game_id: state["game_id"], monster: drawing.monster, part: PARTS[above]).first
        self.class.guide_strip(prev&.strokes.to_a)
      end

      { "monster" => drawing.monster, "part" => drawing.part, "guide" => guide, "strokes" => drawing.strokes, "done" => drawing.done }
    end

    # The bottom of a drawing, moved to the top of a strip (y 0–1 within the strip), so the next
    # artist sees where the neck or the waist ends without seeing the rest. Lines that leave the
    # strip are cut where they cross into it.
    def self.guide_strip(strokes)
      top = 1.0 - GUIDE_STRIP
      strokes.flat_map do |stroke|
        runs   = []
        run    = []
        points = stroke["points"].to_a
        points.each_with_index do |(x, y), i|
          if y >= top
            run << [ points[i - 1][0], top ] if run.empty? && i.positive? # enter at the edge
            run << [ x, y ]
          elsif run.any?
            run << [ x, top ] # leave at the edge
            runs << run
            run = []
          end
        end
        runs << run if run.any?
        runs.map do |r|
          { "color" => stroke["color"], "size" => stroke["size"],
            "points" => r.map { |px, py| [ px.round(4), ((py - top) / GUIDE_STRIP).round(4) ] } }
        end
      end
    end

    # Phone messages can be handled out of order, so strokes are keyed by an id from the phone and
    # saving, undo and clear each work whatever came first (like Doodle Dash).
    def save_stroke!(player_id, stroke)
      return false unless stroke

      id = stroke["id"]
      drawing_update(player_id, { "strokes.id" => { "$ne" => id }, "removed" => { "$ne" => id }, "cleared_upto" => { "$lt" => id },
                                  "strokes.#{MAX_STROKES - 1}" => { "$exists" => false } },
                     "$push" => { "strokes" => stroke })
    end

    def undo!(player_id, id)
      drawing_update(player_id, {}, "$pull" => { "strokes" => { "id" => id } }, "$addToSet" => { "removed" => id })
    end

    def clear!(player_id, upto)
      drawing_update(player_id, {}, "$pull" => { "strokes" => { "id" => { "$lte" => upto } } }, "$max" => { "cleared_upto" => upto })
    end

    # The player taps Done. They can't draw any more this round.
    def done!(player_id)
      pid   = player_id.to_s
      state = fresh_state
      return false unless state["phase"] == "drawing" && current_drawing(pid, state)

      ::MonsterMash::Drawing.where(room_id: @room.id, game_id: state["game_id"], part: PARTS[state["round"]], player_id: pid)
                            .update_all(done: true)
      apply({ "_id" => @room.id, "game_state.phase" => "drawing", "game_state.round" => state["round"] },
            "$set" => { "game_state.done.#{pid}" => true })
    end

    # Players still in the room who have tapped Done.
    def done_ids
      state = fresh_state
      state["done"].to_h.keys & present_ids(state)
    end

    def all_done?
      state = fresh_state
      present_ids(state).all? { |pid| state["done"].to_h.key?(pid) }
    end

    # ── Reveal and vote ──────────────────────────────────────────────────────

    def start_reveal!
      start_phase!("reveal", nil, "game_state.reveal_index" => -1)
    end

    # Moves the reveal on to monster `index` and returns it with its three drawings.
    def reveal!(index)
      @room.atomic_set("game_state.reveal_index" => index)
      monster(index)
    end

    # One monster: name, starter, artists, and the strokes of each part.
    def monster(index)
      state    = @room.game_state
      monster  = state["monsters"].to_a[index]
      return nil unless monster

      drawings = ::MonsterMash::Drawing.where(room_id: @room.id, game_id: state["game_id"], monster: index).to_a.index_by(&:part)
      monster.merge("index" => index, "parts" => PARTS.to_h { |part| [ part, drawings[part]&.strokes.to_a ] })
    end

    def monsters_count
      @room.game_state["monsters"].to_a.size
    end

    def start_vote!(duration)
      start_phase!("vote", duration, "game_state.votes" => {})
    end

    # One vote per player, for any monster but the one they started. The first vote counts.
    def vote!(player_id, index)
      pid   = player_id.to_s
      index = Integer(index, exception: false)
      state = fresh_state
      monster = index && index >= 0 && state["monsters"].to_a[index]
      return false unless state["phase"] == "vote" && monster && present_ids(state).include?(pid)
      return false if monster["starter"] == pid && state["monsters"].size > 1

      apply({ "_id" => @room.id, "game_state.phase" => "vote", "game_state.votes.#{pid}" => { "$exists" => false } },
            "$set" => { "game_state.votes.#{pid}" => index })
    end

    def voted_ids
      state = fresh_state
      state["votes"].to_h.keys & present_ids(state)
    end

    def all_voted?
      state = fresh_state
      present_ids(state).all? { |pid| state["votes"].to_h.key?(pid) }
    end

    # Counts the votes: each vote is a point for every artist of that monster (once each, even if
    # one player drew two of its parts). Returns { tally:, top: [monster indexes], scores:, winners: }.
    def end_vote!
      @room.reload
      state  = @room.game_state
      tally  = state["votes"].to_h.values.tally
      scores = state["scores"].to_h.dup
      tally.each do |index, votes|
        state["monsters"][index]["artists"].values.uniq.each do |pid|
          scores[pid] = scores[pid].to_i + votes if scores.key?(pid)
        end
      end
      top     = tally.empty? ? [] : tally.select { |_, n| n == tally.values.max }.keys.sort
      best    = scores.values.max.to_i
      winners = best.positive? ? scores.select { |_, s| s == best }.keys : []

      results = { "tally" => tally.transform_keys(&:to_s), "top" => top, "winners" => winners }
      start_phase!("results", nil, "game_state.scores" => scores, "game_state.results" => results)
      results.merge("scores" => scores)
    end

    def finish_game!
      @room.reload
      @room.update!(status: "finished", game_state: @room.game_state.merge("phase" => "game_over", "phase_ends_at" => nil))
    end

    # ── Phases ───────────────────────────────────────────────────────────────

    def seconds_left
      ends_at = @room.game_state["phase_ends_at"]
      ends_at && [ (ends_at - Time.now.to_f).ceil, 0 ].max
    end

    # The host's Skip: ends the current phase's wait early (e.g. a long reveal).
    def skip!
      apply({ "_id" => @room.id, "game_state.phase" => { "$in" => %w[reveal results] } }, "$set" => { "game_state.skip" => true })
    end

    def skipped?
      fresh_state["skip"] == true
    end

    # ── What each screen may see ─────────────────────────────────────────────

    INTERNAL_KEYS = %w[loop_id loop_beat skip order].freeze

    # The TV and every phone: no drawings (they come with the reveal), no votes until counted, and
    # each monster's name and artists only once it has been revealed.
    def public_state
      state = @room.game_state
      shown = state.except(*INTERNAL_KEYS, "votes", "done")
      shown["monsters_count"] = state["monsters"].to_a.size
      shown["monsters"] =
        case state["phase"]
        when "reveal" then state["monsters"].to_a.first(state["reveal_index"].to_i + 1)
        when "vote", "results", "game_over" then state["monsters"].to_a
        else []
        end
      shown["part"]          = PARTS[state["round"].to_i] if state["phase"] == "drawing"
      shown["done_ids"]      = state["done"].to_h.keys if state["phase"] == "drawing"
      shown["voted_ids"]     = state["votes"].to_h.keys if state["phase"] == "vote"
      shown["seconds_left"]  = seconds_left
      shown
    end

    def host_state = public_state

    # A phone also gets what it's drawing (and its strokes so far, to carry on after a reload) and
    # its own vote.
    def player_state(player_id)
      pid   = player_id.to_s
      state = @room.game_state
      shown = public_state
      shown["assignment"] = assignment(pid) if state["phase"] == "drawing"
      shown["my_vote"]    = state["votes"].to_h[pid] if state["phase"] == "vote"
      shown["my_monster"] = state["order"].to_a.index(pid)
      shown
    end

    # The game over gallery: every monster with its drawings.
    def gallery
      (0...monsters_count).map { |i| monster(i) }
    end

    private

    def current_drawing(player_id, state)
      return nil unless state["phase"] == "drawing"

      ::MonsterMash::Drawing.where(room_id: @room.id, game_id: state["game_id"], part: PARTS[state["round"].to_i],
                                   player_id: player_id.to_s).first
    end

    # Changes the player's drawing of the current round, if they're still drawing it.
    def drawing_update(player_id, filter, update)
      state = fresh_state
      return false unless state["phase"] == "drawing"

      selector = { "room_id" => @room.id, "game_id" => state["game_id"], "part" => PARTS[state["round"].to_i],
                   "player_id" => player_id.to_s, "done" => false }.merge(filter)
      ::MonsterMash::Drawing.collection.update_one(selector, update).modified_count == 1
    end

    # Players still in the room (a player who left holds nobody up).
    def present_ids(state)
      state["order"].to_a & Player.where(room_id: @room.id).pluck(:id).map(&:to_s)
    end

    def start_phase!(phase, duration, fields = {})
      ends_at = duration && Time.now.to_f + duration.to_i
      @room.atomic_set({ "game_state.phase" => phase, "game_state.phase_ends_at" => ends_at, "game_state.skip" => nil }.merge(fields))
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
