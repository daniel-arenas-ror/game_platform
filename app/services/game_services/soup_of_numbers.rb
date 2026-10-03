module GameServices
  class SoupOfNumbers < Base
    GRID_SIZES   = [ 8, 10, 12, 15 ].freeze
    DIGIT_RANGE  = (2..5)
    ROUND_CHOICES = [ 5, 10, 15 ].freeze

    # Points for finding a number: longer numbers are worth more (2 digits → 100 … 5 digits → 250).
    POINTS_PER_DIGIT = 50

    # Planted numbers read left→right, top→bottom, or diagonally down — never backwards. Players
    # may still claim a copy that reads backwards (made by chance), see #claim!.
    DIRECTIONS = [ [ 0, 1 ], [ 1, 0 ], [ 1, 1 ], [ 1, -1 ] ].freeze

    # One color per player, assigned in join order (cycles when there are more players).
    PLAYER_COLORS = %w[
      #f43f5e #3b82f6 #22c55e #f59e0b #a855f7 #06b6d4
      #ec4899 #84cc16 #f97316 #6366f1 #14b8a6 #eab308
    ].freeze

    PLACEMENT_ATTEMPTS = 200

    def initialize(room)
      @room    = room
      @players = room.players.to_a
    end

    def setup_game!
      grid_size    = @room.game_state["grid_size"].to_i
      grid_size    = 10 unless GRID_SIZES.include?(grid_size)
      max_digits   = (@room.game_state["max_digits"] || 4).to_i.clamp(DIGIT_RANGE.min, DIGIT_RANGE.max)
      total_rounds = (@room.game_state["total_rounds"] || 10).to_i.clamp(1, ROUND_CHOICES.max)
      round_time   = (@room.game_state["round_time"] || 60).to_i.clamp(10, 300)

      grid, targets = self.class.build_soup(grid_size, max_digits, total_rounds)

      @room.update!(
        status: "playing",
        game_state: @room.game_state.merge(
          "status"       => "waiting",
          "loop_running" => false,
          "round"        => 0,
          "total_rounds" => targets.length,
          "grid_size"    => grid_size,
          "max_digits"   => max_digits,
          "round_time"   => round_time,
          "grid"         => grid,
          "targets"      => targets,
          "found"        => [],
          "round_winner" => nil,
          "scores"       => @players.to_h { |p| [ p.id.to_s, 0 ] },
          "colors"       => @players.each_with_index.to_h { |p, i| [ p.id.to_s, PLAYER_COLORS[i % PLAYER_COLORS.length] ] }
        )
      )

      broadcast_start
      true
    end

    # Opens round `round` (1-based) and returns its target. round_ends_at (epoch seconds) lets a
    # reloaded page resume the countdown.
    def start_round!(round)
      @room.atomic_set(
        "game_state.round"         => round,
        "game_state.status"        => "searching",
        "game_state.round_winner"  => nil,
        "game_state.round_ends_at" => Time.now.to_f + @room.game_state["round_time"].to_i
      )
      current_target
    end

    def current_target
      @room.game_state["targets"][@room.game_state["round"].to_i - 1]
    end

    # A player's guess: cells is an Array of [row, col] in the order they were tapped.
    # Returns { ok: true, entry: … } for the first correct claim of the round, otherwise { ok: false }.
    def claim!(player_id, cells)
      @room.reload
      state  = @room.game_state
      target = current_target
      return { ok: false } unless state["status"] == "searching" && target

      cells = self.class.straight_line(cells, state["grid_size"].to_i)
      return { ok: false } unless cells && cells.length == target["number"].length

      # Any copy in the soup counts, in any of the 8 directions, whichever end was tapped first.
      cells = [ cells, cells.reverse ].find { |line| self.class.read(state["grid"], line) == target["number"] }
      return { ok: false } unless cells

      player_id = player_id.to_s
      points    = self.class.points_for(target["number"])
      entry     = { "number" => target["number"], "cells" => cells, "player_id" => player_id, "round" => state["round"] }

      # Only the first correct claim of the round wins, even when two arrive at the same moment.
      result = Room.collection.update_one(
        { "_id" => @room.id, "game_state.status" => "searching", "game_state.round" => state["round"], "game_state.round_winner" => nil },
        {
          "$set"  => { "game_state.round_winner" => player_id, "game_state.status" => "found" },
          "$inc"  => { "game_state.scores.#{player_id}" => points },
          "$push" => { "game_state.found" => entry }
        }
      )
      return { ok: false } unless result.modified_count == 1

      @room.reload
      { ok: true, entry: entry, points: points }
    end

    # Nobody found the number in time: mark the planted copy as found by no one.
    def miss_round!
      target = current_target
      entry  = { "number" => target["number"], "cells" => target["cells"], "player_id" => nil, "round" => @room.game_state["round"] }

      result = Room.collection.update_one(
        { "_id" => @room.id, "game_state.status" => "searching", "game_state.round" => @room.game_state["round"] },
        { "$set" => { "game_state.status" => "missed" }, "$push" => { "game_state.found" => entry } }
      )
      @room.reload
      result.modified_count == 1 ? entry : nil
    end

    # What clients may see: everything except where the targets are hidden and which come next.
    def public_state
      state = @room.game_state.except("targets", "loop_running")
      state.merge("target" => (public_target if state["status"] == "searching"))
    end

    def public_target
      target = current_target
      target && { "number" => target["number"], "length" => target["number"].length, "points" => self.class.points_for(target["number"]) }
    end

    class << self
      def points_for(number)
        number.length * POINTS_PER_DIGIT
      end

      # Builds a grid (Array of digit strings, one per row) with `count` distinct numbers planted in it.
      # Numbers may cross each other where they share a digit. Returns [grid, targets].
      def build_soup(size, max_digits, count)
        cells   = Array.new(size) { Array.new(size) }
        targets = []

        (count * 5).times do
          break if targets.length == count

          number = random_number(rand(DIGIT_RANGE.min..max_digits))
          next if targets.any? { |t| t["number"] == number }

          placed = place(cells, number)
          targets << { "number" => number, "cells" => placed } if placed
        end

        grid = cells.map { |row| row.map { |d| d || rand(10).to_s }.join }
        [ grid, targets ]
      end

      # Returns the tapped cells when they form a straight, gap-free line inside the grid, else nil.
      def straight_line(cells, size)
        return nil unless cells.is_a?(Array) && cells.length >= 2

        cells = cells.map { |c| Array(c).first(2).map { |v| Integer(v, exception: false) } }
        return nil unless cells.all? { |r, c| r && c && r.between?(0, size - 1) && c.between?(0, size - 1) }

        step = [ cells[1][0] - cells[0][0], cells[1][1] - cells[0][1] ]
        return nil unless step.all? { |d| d.abs <= 1 } && step != [ 0, 0 ]
        return nil unless cells.each_cons(2).all? { |a, b| [ b[0] - a[0], b[1] - a[1] ] == step }

        cells
      end

      def read(grid, cells)
        cells.map { |r, c| grid[r][c] }.join
      end

      private

      # No leading zero, so the number on the TV looks like a number.
      def random_number(length)
        rand(1..9).to_s + Array.new(length - 1) { rand(10) }.join
      end

      def place(cells, number)
        size = cells.length

        PLACEMENT_ATTEMPTS.times do
          dr, dc = DIRECTIONS.sample
          r, c   = rand(size), rand(size)
          line   = Array.new(number.length) { |i| [ r + dr * i, c + dc * i ] }

          next unless line.all? { |lr, lc| lr.between?(0, size - 1) && lc.between?(0, size - 1) }
          next unless line.each_with_index.all? { |(lr, lc), i| cells[lr][lc].nil? || cells[lr][lc] == number[i] }

          line.each_with_index { |(lr, lc), i| cells[lr][lc] = number[i] }
          return line
        end

        nil
      end
    end
  end
end
