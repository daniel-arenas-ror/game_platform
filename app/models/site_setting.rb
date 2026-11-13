# Site-wide switches set in the admin (Admin::GamesController), one document for the whole site.
# Pages read them on every request, so each process keeps the value for CACHE_SECONDS: a change
# reaches every server process within that time, without a deploy.
class SiteSetting
  include Mongoid::Document
  include Mongoid::Timestamps

  CACHE_SECONDS = 30

  # The Christmas theme: Santa hat on the logo, snow and lights on the public pages.
  field :christmas, type: Boolean, default: false

  def self.current
    first || create!
  end

  def self.christmas?
    cached.christmas == true
  end

  def self.cached
    @cached = nil if @cached_at.nil? || Time.now - @cached_at > CACHE_SECONDS
    @cached_at = Time.now if @cached.nil?
    @cached ||= current
  end

  def self.reset_cache!
    @cached = @cached_at = nil
  end

  after_save { self.class.reset_cache! }
end
