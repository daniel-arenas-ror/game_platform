require "test_helper"

# The room screens (settings, lobby, join) speak the room's language.
class RoomLocaleFlowTest < ActionDispatch::IntegrationTest
  CODES = %w[fisherman how_want_be_billionare battle_city guess_the_color count_birds sequence_memory
             submarine_combat mind_match soup_of_numbers matching_pairs doodle_dash].freeze

  setup do
    @game = Game.create!(name: "Trivia", code: "how_want_be_billionare", description: "Trivia",
                         translations: { "es" => { "name" => "Trivia ES" } })
    @room = Room.create!(game: @game, locale: "es")
  end

  teardown do
    Player.where(room_id: @room.id).delete_all
    Room.where(id: @room.id).delete_all
    @game.delete
  end

  test "settings page is in Spanish" do
    get edit_room_path(@room.code)
    assert_select "html[lang=es]"
    assert_select "h1", "Configuración de la sala"
    assert_select "input[type=submit][value=?]", "GUARDAR Y LISTO"
    assert_select "label", "NÚMERO DE RONDAS"
  end

  test "every game's settings render in Spanish without missing keys" do
    CODES.each do |code|
      @room.game.update!(code: code)
      get edit_room_path(@room.code)
      assert_response :success, code
      assert_no_match(/translation missing|Translation missing/i, response.body, code)
    end
  ensure
    @game.update!(code: "how_want_be_billionare")
  end

  test "lobby is in Spanish" do
    get room_path(@room.code)
    assert_select "p", "SALA: #{@room.code}"
    assert_select "h1", "Trivia ES"
    assert_select "button", /Empezar juego/
  end

  test "join page is in Spanish and explains a blank nickname" do
    get join_room_path(@room.code)
    assert_select "h1", "Únete a Trivia ES"
    assert_select "input[type=submit][value=?]", "ENTRAR A LA SALA"

    post submit_join_path(@room.code), params: { nickname: "   " }
    assert_response :unprocessable_entity
    assert_select "[role=alert]", "Escribe un apodo"
  end

  test "a removed player is told why, in the room's language" do
    post submit_join_path(@room.code), params: { nickname: "Ana" }
    Player.where(room_id: @room.id).delete_all

    get room_path(@room.code)
    follow_redirect!
    assert_select "[role=alert]", /Estuviste desconectado demasiado tiempo/
  end
end
