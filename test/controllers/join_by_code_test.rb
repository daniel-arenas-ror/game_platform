require "test_helper"

class JoinByCodeTest < ActionDispatch::IntegrationTest
  setup do
    @game = Game.create!(name: "Trivia", code: "how_want_be_billionare", description: "Trivia")
    @room = Room.create!(game: @game)
  end

  teardown do
    Room.where(id: @room.id).delete_all
    @game.delete
  end

  test "home shows the room code form" do
    get root_url
    assert_select "form[action='#{find_room_path}'] input[name=code]"
  end

  test "a known code goes to that room's join page, ignoring case and spaces" do
    get find_room_url(code: " #{@room.code.downcase} ")
    assert_redirected_to join_room_path(@room.code)
  end

  test "an unknown code returns home with an error" do
    get find_room_url(code: "ZZZZ")
    assert_redirected_to root_path
    follow_redirect!
    assert_includes response.body, "No room found with code ZZZZ."
  end
end
