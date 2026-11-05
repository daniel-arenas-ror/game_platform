module GameServices
  # The TV plays a chain of colours that grows by one each round; players repeat it on their phones.
  # The whole chain is drawn at setup and each round shows more of it, so a round can be replayed.
  # Phones never get the sequence before the reveal: see #public_state and #host_state.
  class ColorChain < Base
    COLORS         = %w[blue green yellow red].freeze
    START_LENGTHS  = [ 2, 3, 4 ].freeze
    ROUND_CHOICES  = [ 5, 10, 15 ].freeze

    # Points per correct colour from the start, up to the first mistake.
    POINTS_PER_COLOR = 10

    # TV playback, in seconds: a pause before the first colour, then each colour and the gap after it.
    LEAD_IN        = 1
    FLASH_DURATION = 0.6
    FLASH_GAP      = 0.25

    INTERNAL_KEYS = %w[chain answers loop_id loop_beat].freeze
    REVEALED      = %w[reveal game_over].freeze

    attr_reader :room

    def initialize(room)
      @room    = room
      @players = room.players.to_a
    end

    def setup_game!
      start_length = @room.game_state["start_length"].to_i
      start_length = 3 unless START_LENGTHS.include?(start_length)
      total_rounds = @room.game_state["total_rounds"].to_i
      total_rounds = 10 unless ROUND_CHOICES.include?(total_rounds)

      @room.update!(
        status: "playing",
        game_state: @room.game_state.merge(
          "phase"         => "waiting",
          "loop_id"       => nil,
          "loop_beat"     => nil,
          "round"         => 0,
          "total_rounds"  => total_rounds,
          "start_length"  => start_length,
          "chain"         => Array.new(start_length + total_rounds - 1) { COLORS.sample },
          "phase_ends_at" => nil,
          "scores"        => @players.to_h { |p| [ p.id.to_s, 0 ] },
          "round_scores"  => {},
          "answers"       => {}
        )
      )

      broadcast_start
      true
    end

    # Seconds players get to repeat a sequence.
    def self.input_seconds(length)
      (length * 2 + 3).clamp(7, 30)
    end

    # Seconds the TV needs to play a sequence.
    def self.playback_seconds(length)
      LEAD_IN + (FLASH_DURATION + FLASH_GAP) * length
    end

    # How many colours of the sequence are right from the start.
    def self.correct_colors(sequence, answer)
      return 0 unless answer.is_a?(Array)

      sequence.zip(answer).take_while { |color, tapped| color == tapped }.size
    end

    # A player who came in from the QR during the game.
    def join!(player_id)
      apply({ "_id" => @room.id, "game_state.scores.#{player_id}" => { "$exists" => false } },
            "$set" => { "game_state.scores.#{player_id}" => 0 })
    end

    def start_round!(round)
      @room.atomic_set("game_state.phase" => "watching", "game_state.round" => round, "game_state.answers" => {},
                       "game_state.round_scores" => {}, "game_state.phase_ends_at" => nil)
    end

    def start_input!
      seconds = self.class.input_seconds(sequence.length)
      @room.atomic_set("game_state.phase" => "input", "game_state.phase_ends_at" => Time.now.to_f + seconds)
      seconds
    end

    # One answer per player, while the phones are open. A phone whose time runs out sends what it has.
    def answer!(player_id, colors)
      return false unless colors.is_a?(Array) && (colors - COLORS).empty?

      apply({ "_id" => @room.id, "game_state.phase" => "input", "game_state.scores.#{player_id}" => { "$exists" => true },
              "game_state.answers.#{player_id}" => { "$exists" => false } },
            "$set" => { "game_state.answers.#{player_id}" => colors.first(sequence.length) })
    end

    def all_answered?
      state = @room.class.where(id: @room.id).only(:game_state).first&.game_state.to_h
      ids   = state["scores"].to_h.keys
      ids.any? && (ids - state["answers"].to_h.keys).empty?
    end

    # Closes the phones first, so an answer can't land while the points are counted.
    def score_round!
      return false unless apply({ "_id" => @room.id, "game_state.phase" => "input" }, "$set" => { "game_state.phase" => "scoring" })

      @room.reload
      answers = @room.game_state["answers"].to_h
      points  = @room.game_state["scores"].to_h.keys.to_h do |pid|
        [ pid, self.class.correct_colors(sequence, answers[pid]) * POINTS_PER_COLOR ]
      end
      totals = points.to_h { |pid, won| [ "game_state.scores.#{pid}", @room.game_state["scores"][pid].to_i + won ] }

      @room.atomic_set(totals.merge("game_state.round_scores" => points, "game_state.phase" => "reveal",
                                    "game_state.phase_ends_at" => nil))
      true
    end

    def finish_game!
      @room.reload
      @room.update!(status: "finished", game_state: @room.game_state.merge("phase" => "game_over", "phase_ends_at" => nil))
    end

    def sequence
      state = @room.game_state
      state["chain"].to_a.first(state["start_length"].to_i + state["round"].to_i - 1)
    end

    # What the phones may see: the length of the sequence, and the colours only once it's over.
    def public_state
      shown = @room.game_state.except(*INTERNAL_KEYS)
      shown["sequence_length"] = sequence.length
      shown["answered"]        = @room.game_state["answers"].to_h.keys
      shown["seconds_left"]    = seconds_left
      shown["sequence"]        = sequence if REVEALED.include?(shown["phase"])
      shown
    end

    def host_state = public_state.merge(playback)

    # Sent to the TV alone, on its own stream.
    def playback
      { "sequence" => sequence, "lead_in" => LEAD_IN, "flash_duration" => FLASH_DURATION, "flash_gap" => FLASH_GAP }
    end

    private

    def seconds_left
      ends_at = @room.game_state["phase_ends_at"]
      ends_at ? [ (ends_at - Time.now.to_f).ceil, 0 ].max : nil
    end

    def apply(filter, update)
      changed = Room.collection.update_one(filter, update).modified_count == 1
      @room.reload if changed
      changed
    end
  end
end
