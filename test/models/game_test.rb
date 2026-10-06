require "test_helper"

class GameTest < ActiveSupport::TestCase
  setup do
    tag = SecureRandom.hex(3)
    @games = []
    @popular = make_game("Popular #{tag}", rooms_count: 9)
    @quiet   = make_game("Quiet #{tag}", rooms_count: 1)
    @pinned  = make_game("Pinned #{tag}", rooms_count: 0, position: 1)
    @second  = make_game("Second #{tag}", rooms_count: 0, position: 2)
  end

  teardown do
    Room.where(:game_id.in => @games.map(&:id)).delete_all
    Game.where(:id.in => @games.map(&:id)).delete_all
  end

  test "catalog puts positioned games first, then the most popular" do
    mine = Game.catalog.select { |g| @games.include?(g) }
    assert_equal [ @pinned, @second, @popular, @quiet ], mine
  end

  test "creating a room counts it for its game" do
    assert_difference -> { @quiet.reload.rooms_count }, 2 do
      2.times { Room.create!(game: @quiet) }
    end
  end

  private

  def make_game(name, **attrs)
    Game.create!(name: name, code: "count_birds", description: "x", **attrs).tap { |g| @games << g }
  end
end
