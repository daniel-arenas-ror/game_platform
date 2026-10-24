require "test_helper"

class PagesControllerTest < ActionDispatch::IntegrationTest
  test "privacy, about and contact pages render with the footer" do
    { privacy_path => "Privacy Policy", about_path => "About Grouparty", contact_path => "Contact" }.each do |path, heading|
      get path
      assert_response :success
      assert_select "h1", heading
      assert_select "footer a[href=?]", privacy_path
    end
  end

  test "the privacy policy covers AdSense and the contact email" do
    get privacy_path
    assert_select "a[href=?]", "https://policies.google.com/technologies/partner-sites"
    assert_select "a[href=?]", "mailto:#{PagesController::CONTACT_EMAIL}"
  end

  test "about says in plain words what the site is, for how many players, and how to start" do
    game = Game.create!(name: "Test Game #{SecureRandom.hex(3)}", code: "test_#{SecureRandom.hex(3)}", description: "A test game",
                        min_players: 1, max_players: 99)
    { about_path => [ "1 to 99 players", "Nothing to install", "nobody signs up", "How to start a game" ],
      about_path(locale: "es") => [ "1 a 99 jugadores", "Nada que instalar", "nadie se registra", "Cómo empezar una partida" ] }.each do |path, phrases|
      get path
      assert_response :success
      phrases.each { |phrase| assert_includes response.body, phrase, path }
      assert_select "a[href=?]", game_path(game, locale: path.start_with?("/es") ? "es" : nil)
      assert_select "a[href=?]", find_room_path(locale: path.start_with?("/es") ? "es" : nil)

      graph = JSON.parse(css_select("script[type='application/ld+json']").first.text).fetch("@graph")
      assert_equal %w[Organization WebSite AboutPage FAQPage], graph.map { _1["@type"] }
      assert_operator graph.last["mainEntity"].size, :>=, 5
    end
  ensure
    game&.delete
  end

  test "llms.txt sums up the site and links every public game in both languages" do
    game = Game.create!(name: "Test Game #{SecureRandom.hex(3)}", code: "test_#{SecureRandom.hex(3)}", description: "A test game",
                        slug: "test-game-#{SecureRandom.hex(3)}", min_players: 2, max_players: 8, duration_minutes: 5)
    hidden = Game.create!(name: "Hidden #{SecureRandom.hex(3)}", code: "hidden_#{SecureRandom.hex(3)}", description: "Hidden", listed: false)

    get llms_path
    assert_response :success
    assert_equal "text/plain", response.media_type
    assert_includes response.body, "Nothing to install, no sign-up"
    assert_includes response.body, "[#{game.name}](#{game_url(game)}): A test game 2–8 players, about 5 min."
    assert_includes response.body, game_url(game, locale: "es")
    assert_not_includes response.body, hidden.name
  ensure
    game&.delete
    hidden&.delete
  end

  test "the sitemap lists the new pages" do
    get sitemap_path
    [ about_url, contact_url, privacy_url ].each { |url| assert_includes response.body, url }
  end
end
