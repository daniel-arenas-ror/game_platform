class GameFactory
  def self.build(room)
    case room.game.code.downcase
    when 'fisherman'
      GameServices::Fisherman.new(room)
    when 'how_want_be_billionare'
      GameServices::HowWantBeBillionare.new(room)
    when 'impostor'
      ## TODO
    else
      raise "Game logic not implemented for: #{room.game.name}"
    end
  end
end
