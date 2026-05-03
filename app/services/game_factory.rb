class GameFactory
  def self.build(room)
    case room.game.code.downcase
    when 'fisherman'
      GameServices::Fisherman.new(room)
    when 'quick_draw'
      ## TODO
    when 'impostor'
      ## TODO
    else
      raise "Game logic not implemented for: #{room.game.name}"
    end
  end
end
