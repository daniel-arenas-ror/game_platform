require "test_helper"

class MonsterMashViewsTest < ActionDispatch::IntegrationTest
  setup do
    @game = Game.create!(name: "Monster Mash", code: "monster_mash", description: "Draw")
    @room = Room.create!(game: @game, locale: "es")
  end

  teardown do
    MonsterMash::Drawing.where(room_id: @room.id).delete_all
    Player.where(room_id: @room.id).delete_all
    Event.where(room_id: @room.id).delete_all
    @room.delete
    @game.delete
  end

  test "the drawing time setting renders in the room's language and is saved" do
    get edit_room_path(@room.code, locale: nil)
    assert_response :success
    assert_select "input[name='room[game_state][draw_time]'][value='60'][checked]"
    assert_match "TIEMPO PARA DIBUJAR CADA PARTE", response.body

    patch room_path(@room, locale: nil), params: { room: { game_state: { draw_time: "90" } } }
    GameServices::MonsterMash.new(@room.reload).setup_game!
    assert_equal 90, @room.reload.game_state["draw_time"]
  end

  test "the TV and the phone get their own screens" do
    @room.update!(status: "playing")
    get playing_room_path(@room.code, locale: nil)
    assert_select "[data-controller=monster-mash-host]"

    post submit_join_path(@room.code, locale: nil), params: { nickname: "Ana" }
    get playing_room_path(@room.code, locale: nil)
    assert_select "[data-controller=monster-mash-player] canvas[data-monster-mash-player-target=canvas]"
    assert_select "[data-controller=monster-mash-host]", 0
  end
end
