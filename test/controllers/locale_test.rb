require "test_helper"

class LocaleTest < ActionDispatch::IntegrationTest
  setup do
    @game = Game.create!(name: "Trivia", code: "how_want_be_billionare", description: "Trivia", slug: "trivia-#{SecureRandom.hex(4)}")
    @rooms = []
  end

  teardown do
    Room.where(:id.in => @rooms.map(&:id) + Room.where(game_id: @game.id).pluck(:id)).delete_all
    @game.delete
  end

  test "English has no prefix and Spanish lives under /es" do
    get games_url
    assert_select "html[lang=en]"
    assert_select "#locale-picker option[selected][value=en]"

    get games_url(locale: :es)
    assert_response :success
    assert_select "html[lang=es]"
    assert_select "#locale-picker option[selected][value=es]"
    assert_select "nav[aria-label=Principal] a[href=?]", find_room_path(locale: :es)
  end

  test "public pages list both languages for search engines" do
    get game_url(@game, locale: :es)
    assert_select "link[rel=canonical][href=?]", game_url(@game, locale: :es)
    # Helpers reuse the last request's locale in integration tests, so English is spelled out.
    assert_select "link[rel=alternate][hreflang=en][href=?]", game_url(@game, locale: nil)
    assert_select "link[rel=alternate][hreflang=es][href=?]", game_url(@game, locale: :es)
    assert_select "link[rel=alternate][hreflang=x-default][href=?]", game_url(@game, locale: nil)
  end

  test "the picker remembers the language and returns to the same page in it" do
    get switch_locale_path(lang: "es", return_to: game_path(@game))
    assert_redirected_to game_path(@game, locale: :es)
    assert_equal "es", cookies[:locale]

    get switch_locale_path(lang: "en", return_to: "#{game_path(@game, locale: :es)}?ref=x")
    assert_redirected_to "#{game_path(@game, locale: nil)}?ref=x"
    assert_equal "en", cookies[:locale]
  end

  test "the picker never redirects off the site" do
    [ "//evil.com", "https://evil.com", "/\\evil.com", "/no-such-page" ].each do |target|
      get switch_locale_path(lang: "es", return_to: target)
      assert_redirected_to root_path(locale: :es)
    end

    get switch_locale_path(lang: "fr", return_to: games_path)
    assert_redirected_to games_path
  end

  test "a visitor who picked Spanish is sent to the Spanish page" do
    cookies[:locale] = "es"
    get games_url
    assert_redirected_to games_url(locale: :es)

    cookies[:locale] = "en"
    get games_url
    assert_response :success
  end

  test "a first visit follows the browser language" do
    get games_url, headers: { "Accept-Language" => "es-CO,es;q=0.9,en;q=0.8" }
    assert_redirected_to games_url(locale: :es)

    open_session do |english|
      english.get games_url(locale: nil), headers: { "Accept-Language" => "en-US,en;q=0.9,es;q=0.8" }
      assert_equal 200, english.response.status
    end
  end

  test "a room created from a Spanish page is a Spanish room" do
    post rooms_path(locale: :es, game_id: @game.id)
    room = Room.where(game_id: @game.id).order(created_at: :desc).first
    assert_equal "es", room.locale
    assert_redirected_to edit_room_path(room.code, locale: :es)

    post rooms_path(locale: nil, game_id: @game.id)
    assert_equal "en", Room.where(game_id: @game.id).order(created_at: :desc).first.locale
  end

  test "room pages use the room's language whatever the link or the player's setting" do
    room = Room.create!(game: @game, locale: "es")
    @rooms << room

    cookies[:locale] = "en"
    get join_room_path(room.code)
    assert_response :success
    assert_select "html[lang=es]"
    assert_select "#locale-picker", count: 0

    get room_path(room.code)
    assert_select "html[lang=es]"
    assert_select "#i18n-strings"
  end

  test "the change-game catalog uses the room's language" do
    room = Room.create!(game: @game, locale: "es", status: "finished")
    @rooms << room

    get games_url(room: room.code)
    assert_response :success
    assert_select "html[lang=es]"
    assert_select "#locale-picker", count: 0
  end

  test "rooms only accept languages we have" do
    assert_not Room.new(game: @game, locale: "fr").valid?
    assert_equal "en", Room.new(game: @game).locale
  end

  test "the sitemap lists every page in both languages" do
    get sitemap_url
    assert_response :success
    assert_includes response.body, "<loc>#{games_url}</loc>"
    assert_includes response.body, "<loc>#{games_url(locale: :es)}</loc>"
    assert_includes response.body, %(hreflang="es" href="#{game_url(@game, locale: :es)}")
  end
end

class SpanishPagesTest < ActionDispatch::IntegrationTest
  test "the public pages are in Spanish under /es" do
    { root_path(locale: :es) => "Dale un toque divertido a cualquier reunión.",
      games_path(locale: :es) => "Elige un juego",
      find_room_path(locale: :es) => "¿Tienes un código de sala?",
      about_path(locale: :es) => "Acerca de Grouparty",
      contact_path(locale: :es) => "Contacto",
      privacy_path(locale: :es) => "Política de privacidad" }.each do |path, heading|
      get path
      assert_response :success
      assert_select "h1", heading
      assert_select "nav a", "Inicio"
      assert_select "footer a", "Política de privacidad"
    end
  end

  test "the Spanish home page has a Spanish title and description" do
    get root_path(locale: :es)
    assert_select "title", "Grouparty – Juegos de fiesta gratis que se juegan desde el celular"
    assert_select "meta[property='og:locale'][content=es_LA]"
  end

  test "a wrong room code is explained in Spanish" do
    get find_room_path(locale: :es, code: "ZZZZ")
    follow_redirect!
    assert_select "[role=alert]", /No hay ninguna sala con el código ZZZZ/
  end

  test "Spanish JS strings are on the page" do
    get find_room_path(locale: :es)
    assert_equal "Entrando…", JSON.parse(css_select("#i18n-strings").first.text).dig("room_code", "joining")
  end

  test "every English key has a Spanish one" do
    flatten = ->(hash, prefix = nil) {
      hash.flat_map { |k, v| v.is_a?(Hash) ? flatten.(v, [ prefix, k ].compact.join(".")) : [ [ prefix, k ].compact.join(".") ] }
    }
    # en.yml ↔ es.yml, games/fisherman.en.yml ↔ games/fisherman.es.yml…
    Dir[Rails.root.join("config/locales/{en.yml,games/*.en.yml}")].each do |en_file|
      es_file = en_file.sub(/(\A|\/|\.)en\.yml\z/) { "#{$1}es.yml" }
      assert File.exist?(es_file), "missing #{es_file}"
      en = flatten.(YAML.load_file(en_file)["en"])
      es = flatten.(YAML.load_file(es_file)["es"])
      assert_empty en - es, "missing in #{File.basename(es_file)}"
      assert_empty es - en, "missing in #{File.basename(en_file)}"
    end
  end
end
