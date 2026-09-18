class GameFactory
  def self.build(room)
    case room.game.code.downcase
    when 'fisherman'
      GameServices::Fisherman.new(room)
    when 'how_want_be_billionare'
      GameServices::HowWantBeBillionare.new(room)
    when 'battle_city'
      GameServices::BattleCity.new(room)
    when 'guess_the_color'
      GameServices::GuessTheColor.new(room)
    when 'count_birds'
      GameServices::CountBirds.new(room)
    when 'sequence_memory'
      GameServices::SequenceMemory.new(room)
    when 'submarine_combat'
      GameServices::SubmarineCombat.new(room)
    when 'impostor'
      ## TODO
    else
      raise "Game logic not implemented for: #{room.game.name}"
    end
  end
end
