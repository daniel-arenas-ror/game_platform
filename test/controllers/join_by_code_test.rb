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

  test "join page shows the room code form" do
    get find_room_url
    assert_response :success
    assert_select "h1", "Got a room code?"
    assert_select "a[href=?]", games_path, text: "Pick a game"
    assert_select "form[action='#{find_room_path}'] input[name=code]"
  end

  test "games page no longer has the room code form" do
    get games_url
    assert_select "input[name=code]", count: 0
  end

  test "a known code goes to that room's join page, ignoring case and spaces" do
    get find_room_url(code: " #{@room.code.downcase} ")
    assert_redirected_to join_room_path(@room.code)
  end

  test "an unknown code returns to the join page with an error" do
    get find_room_url(code: "ZZZZ")
    assert_redirected_to find_room_path
    follow_redirect!
    assert_includes response.body, "No room found with code ZZZZ."
    assert_select "input[name=code][value=ZZZZ][aria-invalid=true]"
  end

  test "a blank code asks for one" do
    get find_room_url(code: " ")
    assert_redirected_to find_room_path
    follow_redirect!
    assert_includes response.body, "Enter a room code."
  end

  test "the illustration's example code is never handed out to a real room" do
    codes = [ Room::EXAMPLE_CODE, "AB12" ]
    room = Room.new(game: @game)
    room.define_singleton_method(:random_code) { codes.shift }
    room.save!
    assert_equal "AB12", room.code
  ensure
    room&.delete
  end
end
