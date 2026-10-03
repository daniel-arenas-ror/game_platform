# Static informational pages (privacy, about, contact), linked from the site footer.
class PagesController < ApplicationController
  CONTACT_EMAIL = "contact@grouparty.com".freeze
  GITHUB_URL    = "https://github.com/daniel-arenas-ror".freeze

  before_action { expires_in 1.day, public: true }

  def privacy; end
  def about; end
  def contact; end
end
