# The header's language picker. Remembers the choice, then shows the page the visitor was on
# (return_to) in the new language.
class LocalesController < ApplicationController
  def update
    lang = params[:lang].to_s
    lang = I18n.default_locale.to_s unless I18n.available_locales.map(&:to_s).include?(lang)

    cookies.permanent[LOCALE_COOKIE] = lang
    redirect_to localized_return_path(lang)
  end

  private

  # "/es/games/fisherman" → "/games/fisherman" for English. Anything that isn't one of our pages
  # ("//evil.com", a full URL, a typo) goes to the home page instead.
  def localized_return_path(lang)
    locale = (lang == I18n.default_locale.to_s ? nil : lang)
    path, query = params[:return_to].to_s.split("?", 2)
    return root_path(locale: locale) unless path.start_with?("/") && !path.start_with?("//", "/\\")

    route = Rails.application.routes.recognize_path(path)
    url_for(route.merge(locale: locale, only_path: true)) + (query.present? ? "?#{query}" : "")
  rescue ActionController::RoutingError
    root_path(locale: locale)
  end
end
