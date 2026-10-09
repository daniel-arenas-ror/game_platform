module LocaleHelper
  # Names in their own language, so a visitor finds theirs whatever language the page is in.
  LOCALE_NAMES = { en: "English", es: "Español" }.freeze

  # This page in another language: "/games" ↔ "/es/games".
  def locale_url_for(locale)
    url_for(request.path_parameters.merge(locale: (locale.to_s == I18n.default_locale.to_s ? nil : locale), only_path: false))
  end

  # Strings the Stimulus controllers show, read by controllers/shared/i18n.js.
  def js_translations_tag
    tag.script(I18n.t("js", default: {}).to_json.html_safe, type: "application/json", id: "i18n-strings")
  end
end
