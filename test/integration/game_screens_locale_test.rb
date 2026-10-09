require "test_helper"

# Every game's host and player screens render in a Spanish room with no missing translations
# (the test environment raises on a missing key), and every key the JS asks for exists.
class GameScreensLocaleTest < ActionDispatch::IntegrationTest
  CODES = Room::GAME_STREAM_PREFIXES.keys.freeze

  setup do
    @game = Game.create!(name: "Game", code: CODES.first, description: "A game")
    @room = Room.create!(game: @game, locale: "es", status: "playing")
  end

  teardown do
    Player.where(room_id: @room.id).delete_all
    @room.delete
    @game.delete
  end

  test "every game screen renders in Spanish for the host and a player" do
    host = open_session # no player in its session: the host screen
    post submit_join_path(@room.code), params: { nickname: "Ana" }

    CODES.each do |code|
      @game.update!(code: code)
      @room.update!(status: "playing", game_state: { "question" => "¿Pregunta?", "answereds" => [ "Respuesta" ] })

      get playing_room_path(@room.code)
      assert_response :success, "#{code} (player)"
      assert_select "html[lang=es]"

      host.get playing_room_path(@room.code)
      assert_equal 200, host.response.status, "#{code} (host)"
      strings = JSON.parse(Nokogiri::HTML(host.response.body).at_css("#i18n-strings").text)
      assert_equal [ code ], strings.keys & CODES, "#{code}: only this game's JS strings go to the page"
    end
  end

  test "every key the JS asks for exists in English and Spanish" do
    files = Dir[Rails.root.join("app/javascript/{controllers,channels}/**/*.js")]
    keys  = files.flat_map { |f| File.readlines(f).grep_v(%r{\A\s*//}).join.scan(/\bt\(\s*"([a-z_.0-9]+)"/).flatten }.uniq
    assert_operator keys.size, :>, 100

    %i[en es].each do |locale|
      missing = keys.reject { |key| I18n.exists?("js.#{key}", locale) }
      assert_empty missing, "missing js keys in #{locale}"
    end
  end
end
