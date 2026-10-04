require "test_helper"

class ChangeGameFlowTest < ActionDispatch::IntegrationTest
  setup do
    @trivia = Game.create!(name: "Trivia", code: "how_want_be_billionare", description: "Trivia")
    @color  = Game.create!(name: "Color", code: "guess_the_color", description: "Colors")
    @room   = Room.create!(game: @trivia, status: "finished", game_state: { "total_rounds" => 5 })
  end

  teardown do
    # Only this test's room: tests run in parallel against one database.
    Room.where(id: @room.id).delete_all
    Game.where(:id.in => [ @trivia.id, @color.id ]).delete_all
  end

  test "games page without a room creates new rooms" do
    get games_url
    assert_select "form[action=?]", rooms_path(game_id: @color.id)
    assert_select "form[action=?]", change_game_room_path(@room.code), count: 0
  end

  test "games page with a room offers to switch or configure that room" do
    get games_url(room: @room.code.downcase)
    assert_response :success
    assert_select "form[action=?]", change_game_room_path(@room.code), minimum: 2
    assert_select "button", text: /Configure/, count: 1
    assert_select "a[href=?]", playing_room_path(@room.code), text: "Cancel"
    assert_select "meta[name=robots][content=?]", "noindex, nofollow"
  end

  test "games page ignores an unknown room code" do
    get games_url(room: "ZZZZ")
    assert_response :success
    assert_select "form[action=?]", rooms_path(game_id: @color.id)
  end

  test "old home change-game links redirect to the games page" do
    get root_url(room: @room.code)
    assert_redirected_to games_path(room: @room.code)
  end

  test "game over Change Game link points to the games page" do
    html = ApplicationController.render(partial: "rooms/games/change_game", locals: { room: @room, games: [] })
    assert_includes html, games_path(room: @room.code)
  end

  test "changing game resets the room and goes to configuration" do
    post change_game_room_url(@room.code), params: { game_id: @color.id }
    assert_redirected_to edit_room_path(@room.code)

    @room.reload
    assert_equal @color, @room.game
    assert_equal "lobby", @room.status
    assert_empty @room.game_state
  end
end
