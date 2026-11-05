require "test_helper"

# The host's Game Over screen (rooms/games/_change_game, in every game): a QR for new players, a link
# back to this game's settings and the Change Game link. Players' phones get none of the QR.
class GameOverJoinTest < ActionDispatch::IntegrationTest
  QR = "svg path".freeze

  setup do
    @game = Game.create!(name: "Count Birds", code: "count_birds", description: "x", slug: "count-birds-#{SecureRandom.hex(3)}")
    @room = Room.create!(game: @game, status: "playing")
  end

  teardown do
    Player.where(room_id: @room.id).delete_all
    Room.where(id: @room.id).delete_all
    Game.where(id: @game.id).delete_all
  end

  test "the host gets the join QR, the join address and both links" do
    get playing_room_path(@room.code)
    assert_response :success
    assert_select QR
    assert_includes response.body, "/join/#{@room.code}"
    assert_select "form[action=?] input[name=game_id][value=?]", change_game_room_path(@room.code), @game.id.to_s
    assert_select "form[action=?] button", change_game_room_path(@room.code), "Change settings"
    assert_select "a[href=?]", games_path(room: @room.code), "Change Game"
  end

  test "a player's phone gets no QR" do
    post submit_join_path(@room.code), params: { nickname: "Ana" }
    get playing_room_path(@room.code)
    assert_response :success
    assert_select QR, 0
  end

  test "Change settings keeps the game, sends the room to the lobby and opens the settings" do
    @room.update!(game_state: { "x" => 1 })
    post change_game_room_path(@room.code), params: { game_id: @game.id }
    assert_redirected_to edit_room_path(@room.code)
    @room.reload
    assert_equal [ "lobby", @game.id, {} ], [ @room.status, @room.game_id, @room.game_state ]
  end

  test "a new player can join after the game is over, in either room status" do
    %w[playing finished].each do |status|
      @room.update!(status: status)
      post submit_join_path(@room.code), params: { nickname: "Late #{status}" }
      follow_redirect!
      follow_redirect! if response.redirect?
      assert_response :success, status
      assert @room.players.where(nickname: "Late #{status}").exists?
    end
  end
end
