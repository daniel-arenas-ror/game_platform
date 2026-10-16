require "test_helper"

class HauntedHouseViewsTest < ActionDispatch::IntegrationTest
  setup do
    @game = Game.create!(name: "Haunted House", code: "haunted_house", description: "Boo")
    @room = Room.create!(game: @game, locale: "es")
  end

  teardown do
    Player.where(room_id: @room.id).delete_all
    Event.where(room_id: @room.id).delete_all
    @room.delete
    @game.delete
  end

  test "the settings render in the room's language and are saved" do
    get edit_room_path(@room.code, locale: nil)
    assert_response :success
    assert_select "input[name='room[game_state][discussion_time]'][value='120'][checked]"
    assert_select "input[name='room[game_state][ghosts]'][value='auto'][checked]"
    assert_select "input[name='room[game_state][medium]'][value='true'][checked]"
    assert_select "input[name='room[game_state][reveal_roles]'][value='true'][checked]"
    assert_match "TIEMPO PARA HABLAR", response.body

    patch room_path(@room, locale: nil), params: { room: { game_state: { discussion_time: "60", ghosts: "2", medium: "false", reveal_roles: "false" } } }
    GameServices::HauntedHouse.new(@room.reload).setup_game!
    assert_equal [ 60, "2", false, false ], @room.reload.game_state.values_at("discussion_time", "ghosts", "medium", "reveal_roles")
  end

  test "the TV and the phone get their own screens" do
    @room.update!(status: "playing")
    get playing_room_path(@room.code, locale: nil)
    assert_select "[data-controller=haunted-house-host]"

    post submit_join_path(@room.code, locale: nil), params: { nickname: "Ana" }
    get playing_room_path(@room.code, locale: nil)
    assert_select "[data-controller=haunted-house-player][data-look-tv='Mira la pantalla']"
    assert_select "[data-controller=haunted-house-host]", 0
  end
end
