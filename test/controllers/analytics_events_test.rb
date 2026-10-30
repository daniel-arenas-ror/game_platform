require "test_helper"

class AnalyticsEventsTest < ActionDispatch::IntegrationTest
  setup do
    @game = Game.create!(name: "Mind Match", code: "mind_match", description: "x", slug: "mind-match-#{SecureRandom.hex(3)}")
  end

  teardown do
    rooms = Room.where(game_id: @game.id)
    Player.where(:room_id.in => rooms.pluck(:id)).delete_all
    rooms.delete_all
    Game.where(id: @game.id).delete_all
  end

  test "creating a room queues room_created with the game for the next page" do
    post rooms_path(game_id: @game.id, locale: nil)
    assert_equal [ { "name" => "room_created", "params" => { "game_name" => @game.slug } } ], flash[:analytics_events]
  end

  test "joining a room queues players_joined with the game and the player count, never the nickname" do
    room = Room.create!(game: @game)
    post submit_join_path(room.code, locale: nil), params: { nickname: "Ana" }
    assert_equal [ { "name" => "players_joined", "params" => { "game_name" => @game.slug, "player_count" => 1 } } ],
                 flash[:analytics_events]
  end

  test "the Start game button on the game page sends select_game" do
    get game_path(@game, locale: nil)
    assert_select "form[data-action='submit->analytics#track'][data-analytics-event-param='select_game'][data-analytics-game-param='#{@game.slug}']"
  end
end
