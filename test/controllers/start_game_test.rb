require "test_helper"

class StartGameTest < ActionDispatch::IntegrationTest
  setup do
    @game = Game.create!(name: "Mind Match", code: "mind_match", description: "x", min_players: 3)
    @room = Room.create!(game: @game, status: "lobby")
  end

  teardown do
    # Only this test's records: tests run in parallel against one database.
    Player.where(room_id: @room.id).delete_all
    Room.where(id: @room.id).delete_all
    Game.where(id: @game.id).delete_all
  end

  test "the host can't start an empty room" do
    @game.update!(min_players: nil)

    post start_room_path(@room.code, locale: nil)
    assert_redirected_to room_path(@room.code, locale: nil)
    assert_equal "lobby", @room.reload.status

    follow_redirect!
    assert_select "#start-warning:not(.hidden)", text: /Nobody is in the lobby yet/
  end

  test "the host can't start with fewer players than the game needs" do
    @room.players.create!(nickname: "Ana")
    @room.players.create!(nickname: "Bob")

    post start_room_path(@room.code, locale: nil)
    assert_redirected_to room_path(@room.code, locale: nil)
    assert_equal "lobby", @room.reload.status
    assert_equal "Not enough players yet. You need at least 3 players to start this game.", flash[:alert]
  end

  test "the lobby keeps the warning hidden until the host tries to start" do
    get room_path(@room.code, locale: nil)
    assert_select "#start-warning.hidden"
    assert_select "[data-game-subscription-min-players-value='3']"
  end
end
