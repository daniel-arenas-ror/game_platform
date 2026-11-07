require "test_helper"

class AnalyticsEventsTest < ActionDispatch::IntegrationTest
  include ActionCable::TestHelper

  setup do
    @game = Game.create!(name: "Mind Match", code: "mind_match", description: "x", slug: "mind-match-#{SecureRandom.hex(3)}")
  end

  teardown do
    rooms = Room.where(game_id: @game.id)
    Player.where(:room_id.in => rooms.pluck(:id)).delete_all
    rooms.delete_all
    Game.where(id: @game.id).delete_all
  end

  def params_of(room, player_count:)
    { "game" => @game.slug, "game_name" => @game.slug, "room_code" => room.code, "player_count" => player_count, "game_language" => "en" }
  end

  def sent_on(room) = broadcasts(RoomChannel.stream_for_room(room.code)).map { JSON.parse(_1) }.select { _1["action"] == "analytics" }
  def events_on(room) = sent_on(room).map { _1["event"] }

  test "creating a room queues room_created with the room's parameters for the next page" do
    post rooms_path(game_id: @game.id, locale: nil)
    room = Room.where(game_id: @game.id).last
    assert_equal [ { "name" => "room_created", "params" => params_of(room, player_count: 0) } ], flash[:analytics_events]
  end

  test "joining a room queues players_joined with the room's parameters, never the nickname" do
    room = Room.create!(game: @game)
    post submit_join_path(room.code, locale: nil), params: { nickname: "Ana" }
    assert_equal [ { "name" => "players_joined", "params" => params_of(room, player_count: 1) } ], flash[:analytics_events]
  end

  test "one game sends one game_started and one game_finished, with the room's parameters" do
    room = Room.create!(game: @game, locale: "es")
    room.players.create!(nickname: "Ana")

    room.update!(status: "playing")
    room.update!(game_state: { "round" => 2 }) # a round going by
    room.update!(status: "playing")
    room.update!(status: "finished")
    room.update!(status: "finished")

    assert_equal %w[game_started game_finished], events_on(room)
    assert_equal params_of(room, player_count: 1).merge("game_language" => "es"), sent_on(room).first["params"]
  end

  test "play again is its own event, and a new game after changing game is a new game_started" do
    room = Room.create!(game: @game)
    %w[playing finished playing finished lobby playing].each { room.update!(status: _1) }
    assert_equal %w[game_started game_finished play_again game_finished game_started], events_on(room)
  end

  test "a start the server refuses sends nothing" do
    @game.update!(code: "submarine_combat") # needs 2 players
    room = Room.create!(game: @game)
    post start_room_path(room.code, locale: nil)
    assert_response :redirect
    assert_equal "lobby", room.reload.status
    assert_empty events_on(room)
  end

  test "the Start game button on the game page sends select_game" do
    get game_path(@game, locale: nil)
    assert_select "form[data-action='submit->analytics#track'][data-analytics-event-param='select_game'][data-analytics-game-param='#{@game.slug}'][data-analytics-language-param='en']"
  end
end
