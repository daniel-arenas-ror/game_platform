module LocaleHelper
  # Names in their own language, so a visitor finds theirs whatever language the page is in.
  LOCALE_NAMES = { en: "English", es: "Español" }.freeze

  # This page in another language: "/games" ↔ "/es/games".
  def locale_url_for(locale)
    url_for(request.path_parameters.merge(locale: (locale.to_s == I18n.default_locale.to_s ? nil : locale), only_path: false))
  end

  # Strings the Stimulus controllers show, read by controllers/shared/i18n.js. Each game's strings
  # (js.<code>) only go to that game's screens; the rest (shared, room_code…) go everywhere.
  def js_translations_tag
    strings = I18n.t("js", default: {})
    current = @room&.game&.code&.to_sym
    strings = strings.reject { |key, _| Room::GAME_STREAM_PREFIXES.key?(key.to_s) && key != current }
    tag.script(strings.to_json.html_safe, type: "application/json", id: "i18n-strings")
  end
end
