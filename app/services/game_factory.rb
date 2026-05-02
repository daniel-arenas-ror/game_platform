class GameFactory
  def self.build(room)
    case room.game.code.downcase
    when 'fisherman'
      GameServices::FishermanManager.new(room)
    when 'quick draw'
      ## TODO
    when 'impostor'
      ## TODO
    else
      raise "Game logic not implemented for: #{room.game.name}"
    end
  end
end
