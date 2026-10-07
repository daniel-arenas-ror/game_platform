module Admin
  # Every admin page: signed-in admins only, never indexed or cached, no ads, its own layout.
  class BaseController < ApplicationController
    layout "admin"

    before_action :authenticate_admin_user!
    before_action :private_headers

    private

    def private_headers
      response.set_header("X-Robots-Tag", "noindex, nofollow")
      response.set_header("Cache-Control", "no-store")
    end
  end
end
