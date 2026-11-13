require "test_helper"

class AdminGamesTest < ActionDispatch::IntegrationTest
  PASSWORD = "correct horse battery".freeze

  setup do
    Admin::SessionsController::RATE_LIMIT_STORE.clear
    @admin = AdminUser.create!(email: "admin-#{SecureRandom.hex(4)}@example.com", password: PASSWORD)
    tag    = SecureRandom.hex(3)
    @first  = Game.create!(name: "Admin Order A #{tag}", code: "fisherman", description: "x", rooms_count: 1)
    @second = Game.create!(name: "Admin Order B #{tag}", code: "fisherman", description: "x", rooms_count: 9)
  end

  teardown do
    # Only this test's records: tests run in parallel against one database.
    Game.where(:id.in => [ @first.id, @second.id ]).delete_all
    @admin.delete
  end

  def log_in
    post admin_user_session_path, params: { admin_user: { email: @admin.email, password: PASSWORD } }
  end

  def save(first, second)
    patch admin_games_path, params: { games: { @first.id.to_s => first, @second.id.to_s => second } }
  end

  test "the games page needs a login" do
    get admin_games_path
    assert_redirected_to new_admin_user_session_path
    patch admin_games_path, params: { games: { @first.id.to_s => { position: "1", listed: "0" } } }
    assert_redirected_to new_admin_user_session_path
    assert @first.reload.listed
  end

  test "lists every game with its position and shown switch, linked from the menu" do
    @second.update!(listed: false)
    log_in
    get admin_games_path
    assert_response :success
    assert_select "nav[aria-label=Admin] a[aria-current=page]", "Games"
    assert_select "td", text: /#{@first.name}/
    assert_select "input[name=?][type=checkbox][checked]", "games[#{@first.id}][listed]"
    assert_select "input[name=?][type=checkbox]:not([checked])", "games[#{@second.id}][listed]"
  end

  test "saves the order and who is shown, and a blank position goes back to popularity" do
    log_in
    save({ position: "2", listed: "1" }, { position: "1", listed: "0" })
    assert_redirected_to admin_games_path
    assert_equal [ 2, true ], [ @first.reload.position, @first.listed ]
    assert_equal [ 1, false ], [ @second.reload.position, @second.listed ]

    save({ position: "", listed: "1" }, { position: "5000", listed: "1" })
    assert_nil @first.reload.position
    assert_equal [ Admin::GamesController::MAX_POSITION, true ], [ @second.reload.position, @second.listed ]
  end

  test "the catalog follows the saved order" do
    log_in
    save({ position: "1", listed: "1" }, { position: "", listed: "1" })
    order = Game.in_catalog_order([ @second.reload, @first.reload ]).map(&:id)
    assert_equal [ @first.id, @second.id ], order, "a numbered game goes before a more popular one"
  end

  # Flips its own SiteSetting, not the one every other test reads (SiteSetting.current is the oldest),
  # so tests running in parallel never see Christmas mode on.
  test "the Christmas switch needs a login, then turns the mode on and off" do
    SiteSetting.first || SiteSetting.create!
    mine     = SiteSetting.create!
    original = SiteSetting.method(:current)
    SiteSetting.define_singleton_method(:current) { mine }
    SiteSetting.reset_cache!

    patch admin_settings_path, params: { christmas: "1" }
    assert_redirected_to new_admin_user_session_path

    log_in
    patch admin_settings_path, params: { christmas: "1" }
    assert_redirected_to admin_games_path
    assert mine.reload.christmas
    get admin_games_path
    assert_select "#christmas-mode", /On/

    patch admin_settings_path, params: { christmas: "0" }
    assert_not mine.reload.christmas
  ensure
    SiteSetting.define_singleton_method(:current, original)
    SiteSetting.reset_cache!
    mine&.delete
  end
end
