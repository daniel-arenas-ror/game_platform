require "test_helper"

# Smoke test: every implemented game can be set up through GameFactory.
class GameSetupTest < ActiveSupport::TestCase
  CODES = %w[fisherman how_want_be_billionare battle_city guess_the_color count_birds
             sequence_memory submarine_combat mind_match].freeze

  setup do
    @records = [
      Fisherman::Question.create!(text: "Q?", answerds: [ "A" ]),
      HowWantBeBillionare::Question.create!(text: "Q?", points: 100, topic: "T",
                                             answers: [ { text: "A", correct: true }, { text: "B", correct: false } ]),
      BattleCity::MapPreset.create!(name: "classic", base_x: 12, base_y: 24,
                                    tank_spawns: [ { "x" => 2, "y" => 2 }, { "x" => 23, "y" => 2 },
                                                   { "x" => 2, "y" => 22 }, { "x" => 23, "y" => 22 } ])
    ]
  end

  teardown do
    @records.each(&:delete)
  end

  CODES.each do |code|
    test "#{code} sets up and starts playing" do
      game = Game.create!(name: code, code: code, description: "x")
      room = Room.create!(game: game)
      %w[Ana Beto Caro].each { |n| room.players.create!(nickname: n) }
      @records.push(game, room)

      assert GameFactory.build(room).setup_game!
      assert_equal "playing", room.reload.status
    ensure
      Player.where(room_id: room&.id).delete_all
    end
  end
end
