class ApplicationController < ActionController::Base
  LOCALE_COOKIE = :locale

  # Only allow modern browsers supporting webp images, web push, badges, import maps, CSS nesting, and CSS :has.
  allow_browser versions: :modern
  helper_method :current_player

  around_action :switch_locale
  before_action :redirect_to_preferred_locale

  # Changes to the importmap will invalidate the etag for HTML responses
  stale_when_importmap_changes

  def current_player
    @current_player ||= Player.find(session[:player_id]) if session[:player_id]
  rescue Mongoid::Errors::DocumentNotFound
    session[:player_id] = nil
    nil
  end

  # English URLs have no prefix ("/games"), Spanish ones do ("/es/games").
  def default_url_options
    { locale: (I18n.locale == I18n.default_locale ? nil : I18n.locale) }
  end

  private

  # The URL decides the language. Controllers that work inside a room override #room_locale,
  # so everyone in that room gets the room's language whatever link they came from.
  def switch_locale(&action)
    locale = room_locale.presence || params[:locale].presence || I18n.default_locale
    locale = I18n.default_locale unless I18n.available_locales.map(&:to_s).include?(locale.to_s)
    I18n.with_locale(locale, &action)
  end

  def room_locale
    nil
  end

  # Public pages without a prefix send visitors who prefer Spanish (picked in the header, or
  # their browser's language on a first visit) to the Spanish page. Crawlers have neither, so
  # they index both versions.
  def redirect_to_preferred_locale
    return unless request.get? && request.format.html? && params[:locale].blank? && room_locale.blank?
    return unless helpers.site_header?

    preferred = cookies[LOCALE_COOKIE].presence || browser_locale
    return if preferred.blank? || preferred.to_s == I18n.default_locale.to_s

    cookies.permanent[LOCALE_COOKIE] = preferred
    redirect_to url_for(request.path_parameters.merge(locale: preferred, params: request.query_parameters))
  end

  # A browser language we have ("es-CO" → "es") when it comes before English, else nil.
  def browser_locale
    request.headers["Accept-Language"].to_s.split(",").each do |entry|
      lang = entry.split(";").first.to_s.strip.first(2).downcase
      return nil if lang == I18n.default_locale.to_s
      return lang if I18n.available_locales.map(&:to_s).include?(lang)
    end
    nil
  end
end
