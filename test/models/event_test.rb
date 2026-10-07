require "test_helper"

class EventTest < ActiveSupport::TestCase
  setup do
    @game = Game.create!(name: "Count Birds", code: "count_birds", description: "x")
    @room = Room.create!(game: @game)
  end

  teardown do
    Event.where(room_id: @room.id).delete_all
    Player.where(room_id: @room.id).delete_all
    @room.delete
    @game.delete
  end

  def events(kind) = Event.where(room_id: @room.id, kind: kind).to_a

  test "creating a room is recorded once, with its game" do
    assert_equal 1, events(:room_created).size
    assert_equal @game.id, events(:room_created).first.game_id
  end

  test "each player joining is recorded, and stays counted after they leave" do
    ana = @room.players.create!(nickname: "Ana")
    @room.players.create!(nickname: "Beto")
    ana.destroy

    assert_equal 2, events(:player_joined).size
    assert events(:player_joined).none? { |e| e.attributes.key?("nickname") }
  end

  test "starting a game is recorded with the players in it, and play again is marked" do
    2.times { |i| @room.players.create!(nickname: "P#{i}") }

    GameFactory.build(@room).setup_game!
    GameServices::CountBirds.new(Room.find(@room.id)).setup_game!

    started = events(:game_started).sort_by(&:created_at)
    assert_equal [ 2, 2 ], started.map(&:players)
    assert_equal [ false, true ], started.map(&:again)
    assert_equal [ @game.id ] * 2, started.map(&:game_id)
  end

  test "every game counts its starts" do
    games = Dir[Rails.root.join("app/services/game_services/*.rb")].map { "GameServices::#{File.basename(_1, '.rb').camelize}".constantize }
    assert_operator games.size, :>, 10
    games.without(GameServices::Base).each do |game|
      assert game.ancestors.index(GameServices::Base::TrackStart) < game.ancestors.index(game), "#{game} isn't tracked"
    end
  end

  test "a failed write never breaks the game" do
    assert_nil Event.record(:nonsense, room: @room)
  end

  test "old rooms get their room_created event back, once" do
    Event.where(room_id: @room.id).delete_all
    @room.set(created_at: 3.days.ago)
    require "rake"
    Rails.application.load_tasks unless Rake::Task.task_defined?("events:backfill_rooms")

    2.times { capture_io { Rake::Task["events:backfill_rooms"].tap(&:reenable).invoke } }

    assert_equal 1, events(:room_created).size
    assert_in_delta 3.days.ago, events(:room_created).first.created_at, 5
  end
end
