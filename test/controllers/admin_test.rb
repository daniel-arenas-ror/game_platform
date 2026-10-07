require "test_helper"

class AdminTest < ActionDispatch::IntegrationTest
  PASSWORD = "correct horse battery".freeze

  setup do
    Admin::SessionsController::RATE_LIMIT_STORE.clear
    @admin = AdminUser.create!(email: "admin-#{SecureRandom.hex(4)}@example.com", password: PASSWORD)
  end

  teardown { @admin.delete }

  def log_in(password = PASSWORD, email: @admin.email)
    post admin_user_session_path, params: { admin_user: { email: email, password: password } }
  end

  test "the stats need a login" do
    get admin_root_path
    assert_redirected_to new_admin_user_session_path
  end

  test "an admin logs in, sees the stats, and logs out" do
    log_in
    assert_redirected_to admin_root_path

    get admin_root_path
    assert_response :success
    assert_select "h1", "Stats"
    assert_equal "noindex, nofollow", response.headers["X-Robots-Tag"]
    assert_includes response.headers["Cache-Control"], "no-store"

    delete destroy_admin_user_session_path
    get admin_root_path
    assert_redirected_to new_admin_user_session_path
  end

  test "the admin pages have no ads, no SEO tags and are never indexed" do
    get new_admin_user_session_path
    assert_response :success
    assert_select "meta[name=robots][content='noindex, nofollow']"
    assert_no_match(/adsbygoogle|pagead2|og:image|canonical/, response.body)
  end

  test "a wrong password and an unknown email look the same" do
    log_in("wrong password")
    wrong_password = flash[:alert]
    log_in(email: "nobody@example.com")

    assert_response :unprocessable_content
    assert_equal wrong_password, flash[:alert]
  end

  test "the account locks after 10 wrong passwords" do
    @admin.update!(failed_attempts: Devise.maximum_attempts - 1)
    log_in("wrong password")
    assert @admin.reload.access_locked?

    Admin::SessionsController::RATE_LIMIT_STORE.clear
    log_in
    assert_not_equal admin_root_path, response.location
  end

  test "each IP gets 5 login tries a minute" do
    5.times { log_in("wrong password") }
    log_in

    assert_redirected_to new_admin_user_session_path
    assert_match(/Too many attempts/, flash[:alert])
  end

  test "there is no sign-up or password reset" do
    assert_not Rails.application.routes.url_helpers.respond_to?(:new_admin_user_registration_path)
    assert_not Rails.application.routes.url_helpers.respond_to?(:new_admin_user_password_path)
  end

  test "nothing on the site points to the admin" do
    [ root_path, games_path, sitemap_path, robots_path ].each do |path|
      get path
      assert_not_includes response.body, new_admin_user_session_path, "#{path} mentions the admin"
    end
  end
end
