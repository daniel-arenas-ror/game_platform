require "test_helper"

class ChangeGameFlowTest < ActionDispatch::IntegrationTest
  setup do
    @trivia = Game.create!(name: "Trivia", code: "how_want_be_billionare", description: "Trivia")
    @color  = Game.create!(name: "Color", code: "guess_the_color", description: "Colors")
    @room   = Room.create!(game: @trivia, status: "finished", game_state: { "total_rounds" => 5 })
  end

  teardown do
    Room.delete_all
    Game.where(:id.in => [ @trivia.id, @color.id ]).delete_all
  end

  test "home without a room creates new rooms" do
    get root_url
    assert_select "form[action=?]", rooms_path(game_id: @color.id)
    assert_select "form[action=?]", change_game_room_path(@room.code), count: 0
  end

  test "home with a room offers to switch or configure that room" do
    get root_url(room: @room.code.downcase)
    assert_response :success
    assert_select "form[action=?]", change_game_room_path(@room.code), minimum: 2
    assert_select "button", text: /Configure/, count: 1
    assert_select "a[href=?]", playing_room_path(@room.code), text: "Cancel"
  end

  test "home ignores an unknown room code" do
    get root_url(room: "ZZZZ")
    assert_response :success
    assert_select "form[action=?]", rooms_path(game_id: @color.id)
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
