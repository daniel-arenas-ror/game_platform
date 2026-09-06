module GameServices
  class BattleCity < Base
    TANK_COLORS = %w[yellow green white red].freeze

    def initialize(room)
      @room = room
      @players = room.players.to_a
    end

    def setup_game!
      @room.update!(status: 'playing')
      broadcast_start
      true
    end
  end
end
