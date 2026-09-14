module GameServices
  class CountBirds < Base
    # How many black birds appear in each round.
    # Base = round number + 4, with ±2 randomness, minimum 3.
    def self.bird_count_for(round)
      base = round + 4
      [base + rand(-2..2), 3].max
    end

    # Difficulty tier drives animation + distractor config sent to the host canvas.
    # The client uses these params — the server only tracks counts and scores.
    def self.difficulty_for(round)
      case round
      when 1..5   then "static"
      when 6..11  then "moving"
      else             "chaos"
      end
    end

    # Number of distractor elements (colored shapes / non-black birds).
    def self.distractor_count_for(round)
      return 0 if round < 6
      ((round - 5) * 1.5).round.clamp(1, 15)
    end

    # Scoring: exact = 100pts, off by 1 = 50pts, anything else = 0.
    def self.calculate_score(correct, guess)
      return 0  unless guess
      diff = (correct.to_i - guess.to_i).abs
      case diff
      when 0 then 100
      when 1 then 50
      else        0
      end
    end

    def initialize(room)
      @room    = room
      @players = room.players.to_a
    end

    def setup_game!
      total_rounds = (@room.game_state["total_rounds"] || 10).to_i
      scores       = @players.each_with_object({}) { |p, h| h[p.id.to_s] = 0 }

      @room.update!(
        status: "playing",
        game_state: @room.game_state.merge(
          "status"       => "waiting",
          "round"        => 0,
          "total_rounds" => total_rounds,
          "scores"       => scores,
          "bird_count"   => nil,
          "picks"        => {},
          "round_scores" => {}
        )
      )

      broadcast_start
      true
    end
  end
end
