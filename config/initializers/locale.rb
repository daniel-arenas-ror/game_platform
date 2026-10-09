# English lives at "/", Spanish under "/es". A room keeps the language it was created in.
I18n.available_locales = %i[en es]
I18n.default_locale = :en
I18n.enforce_available_locales = true

# Each game's in-game strings live in config/locales/games/<code>.<locale>.yml.
Rails.application.config.i18n.load_path += Dir[Rails.root.join("config/locales/games/*.yml")]
