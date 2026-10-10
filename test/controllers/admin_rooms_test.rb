require "test_helper"

class AdminRoomsTest < ActionDispatch::IntegrationTest
  PASSWORD = "correct horse battery".freeze

  setup do
    Admin::SessionsController::RATE_LIMIT_STORE.clear
    @admin = AdminUser.create!(email: "admin-#{SecureRandom.hex(4)}@example.com", password: PASSWORD)
    @game  = Game.create!(name: "Admin Trivia #{SecureRandom.hex(2)}", code: "how_want_be_billionare", description: "x")
    @room  = Room.create!(game: @game, status: "playing", locale: "es", game_state: { "user_points" => {} })
    @ana   = @room.players.create!(nickname: "Ana", connected: true, connections: 1)
    @room.atomic_set("game_state.user_points" => { @ana.id.to_s => 300 })
    Event.record(:game_started, room: @room, players: 1)
  end

  teardown do
    # Only this test's records: tests run in parallel against one database.
    Event.where(room_id: @room.id).delete_all
    Player.where(room_id: @room.id).delete_all
    Room.where(id: @room.id).delete_all
    Game.where(id: @game.id).delete_all
    @admin.delete
  end

  def log_in
    post admin_user_session_path, params: { admin_user: { email: @admin.email, password: PASSWORD } }
  end

  test "the rooms pages need a login" do
    get admin_rooms_path
    assert_redirected_to new_admin_user_session_path
    get admin_room_path(@room)
    assert_redirected_to new_admin_user_session_path
  end

  test "the menu links the dashboard and the rooms, marking the current page" do
    log_in
    get admin_root_path
    assert_select "nav[aria-label=Admin] a[aria-current=page]", "Dashboard"
    get admin_rooms_path
    assert_select "nav[aria-label=Admin] a[aria-current=page]", "Rooms"
  end

  test "the list shows the room and filters by game, status and code" do
    log_in
    get admin_rooms_path(game: @game.id)
    assert_response :success
    assert_select "a[href=?]", admin_room_path(@room), text: @room.code
    assert_select "tbody tr", 1
    assert_select "tbody tr td", text: @game.name

    get admin_rooms_path(game: @game.id, status: "finished")
    assert_select "tbody tr", 0

    get admin_rooms_path(game: @game.id, q: @room.code.downcase)
    assert_select "tbody tr", 1
  end

  test "a room's details show its players, history and game state" do
    log_in
    get admin_room_path(@room)
    assert_response :success
    assert_select "h1", @room.code
    assert_select "#players + div td", text: "Ana"
    assert_select "#players + div td", text: "300"
    assert_select "ol li", text: /Game started/
    assert_select "pre", text: /user_points/
  end

  test "an unknown room goes back to the list" do
    log_in
    get admin_room_path("000000000000000000000000")
    assert_redirected_to admin_rooms_path
  end
end
