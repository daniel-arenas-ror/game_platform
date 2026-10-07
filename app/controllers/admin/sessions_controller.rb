module Admin
  # The admin login. On top of Devise's lockable (per account), each IP gets 5 tries a minute.
  class SessionsController < Devise::SessionsController
    # Its own store: the app's cache is a null store in tests, which would turn the limit off.
    RATE_LIMIT_STORE = ActiveSupport::Cache::MemoryStore.new

    layout "admin"

    rate_limit to: 5, within: 1.minute, only: :create, store: RATE_LIMIT_STORE,
               with: -> { redirect_to new_admin_user_session_path, alert: "Too many attempts. Wait a minute and try again." }

    before_action { response.set_header("X-Robots-Tag", "noindex, nofollow") }

    private

    def after_sign_in_path_for(_admin) = admin_root_path
    def after_sign_out_path_for(_admin) = new_admin_user_session_path
  end
end
