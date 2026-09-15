module GameServices
  class SequenceMemory < Base
    # Points awarded per consecutive correct step from the start.
    POINTS_PER_STEP = 10

    # How long each cell stays highlighted during playback (seconds).
    FLASH_DURATION = 0.6

    # Gap between flashes (seconds).
    FLASH_GAP = 0.25

    def initialize(room)
      @room    = room
      @players = room.players.to_a
    end

    def setup_game!
      total_rounds = (@room.game_state["total_rounds"] || 10).to_i
      grid_size    = (@room.game_state["grid_size"]    || 4).to_i
      scores       = @players.each_with_object({}) { |p, h| h[p.id.to_s] = 0 }

      @room.update!(
        status: "playing",
        game_state: @room.game_state.merge(
          "status"       => "waiting",
          "round"        => 0,
          "total_rounds" => total_rounds,
          "grid_size"    => grid_size,
          "sequence"     => [],
          "scores"       => scores,
          "submissions"  => {},
          "round_scores" => {}
        )
      )

      broadcast_start
      true
    end

    # Appends one random cell index to the stored sequence and returns the full sequence.
    # Cell indices are 0-based (0 to grid_size²-1).
    def next_sequence!
      grid_size = (@room.game_state["grid_size"] || 4).to_i
      sequence  = @room.game_state["sequence"] || []
      cell      = rand(grid_size * grid_size)
      sequence  = sequence + [cell]
      @room.set("game_state.sequence" => sequence)
      sequence
    end

    # Input window for players: starts at 7s, grows by 2s per round, capped at 30s.
    def self.input_duration_for(round)
      (5 + round * 2).clamp(7, 30)
    end

    # Playback duration the server must sleep while the host animates the sequence.
    def self.playback_duration_for(sequence_length)
      ((FLASH_DURATION + FLASH_GAP) * sequence_length + 0.5).ceil
    end

    # Partial credit: 10pts per consecutive correct step from index 0.
    # Stops counting at the first wrong cell.
    def self.calculate_score(sequence, submission)
      return 0 unless submission.is_a?(Array) && sequence.is_a?(Array)
      correct = 0
      sequence.each_with_index do |cell, i|
        break unless submission[i] == cell
        correct += 1
      end
      correct * POINTS_PER_STEP
    end
  end
end
