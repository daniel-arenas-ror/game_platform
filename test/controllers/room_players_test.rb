require "test_helper"

class RoomPlayersTest < ActionDispatch::IntegrationTest
  include ActionCable::TestHelper

  setup do
    @game = Game.create!(name: "Mind Match", code: "mind_match", description: "x")
    @room = Room.create!(game: @game, status: "lobby")
    @ana  = @room.players.create!(nickname: "Ana", connected: true)
    @bob  = @room.players.create!(nickname: "Bob")
  end

  teardown do
    # Only this test's records: tests run in parallel against one database.
    Player.where(room_id: @room.id).delete_all
    Room.where(id: @room.id).delete_all
    Game.where(id: @game.id).delete_all
  end

  test "the host lists the room's players" do
    get players_room_path(@room.code, locale: nil), as: :json
    assert_response :success
    assert_equal [ [ "Ana", true ], [ "Bob", false ] ], response.parsed_body.map { |p| p.values_at("nickname", "connected") }
  end

  test "the host removes a player and the player's phone is told" do
    assert_broadcast_on(RoomChannel.stream_for_room(@room.code), action: "player_left", player_id: @bob.id.to_s, nickname: "Bob") do
      delete remove_player_room_path(@room.code, @bob.id, locale: nil)
    end
    assert_response :no_content
    assert_nil Player.where(id: @bob.id).first
    assert Player.where(id: @ana.id).exists?
  end

  test "players can't list or remove anyone" do
    post submit_join_path(@room.code, locale: nil), params: { nickname: "Cleo" }

    get players_room_path(@room.code, locale: nil), as: :json
    assert_response :forbidden
    delete remove_player_room_path(@room.code, @bob.id, locale: nil)
    assert_response :forbidden
    assert Player.where(id: @bob.id).exists?
  end

  test "only the host sees the Players button" do
    get room_path(@room.code, locale: nil)
    assert_select "[data-controller=room-players] button", text: /Players/

    post submit_join_path(@room.code, locale: nil), params: { nickname: "Cleo" }
    get room_path(@room.code, locale: nil)
    assert_select "[data-controller=room-players]"
    assert_select "[data-controller=room-players] button", count: 0
  end

  test "the lobby list has a remove button per player, for the host only" do
    get room_path(@room.code, locale: nil)
    assert_select "#player-list button[data-action='game-subscription#remove'][data-player-id=?]", @bob.id.to_s, text: "Remove"
    assert_select "#player-list button[data-action='game-subscription#remove']", count: 2

    post submit_join_path(@room.code, locale: nil), params: { nickname: "Cleo" }
    get room_path(@room.code, locale: nil)
    assert_select "#player-list button", count: 0
  end

  test "the panel is on the game screen too" do
    @room.update!(status: "playing")
    get playing_room_path(@room.code, locale: nil)
    assert_select "[data-controller=room-players] dialog"
  end

  test "a removed player lands on the join page with a message" do
    @room.update!(locale: "es")
    get join_room_path(@room.code, removed: "host", locale: nil)
    assert_select "[role=alert]", text: /El anfitrión te sacó de la sala/
  end
end
