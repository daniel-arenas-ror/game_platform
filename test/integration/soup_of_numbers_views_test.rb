require "test_helper"

class SoupOfNumbersViewsTest < ActionDispatch::IntegrationTest
  setup do
    @game = Game.create!(name: "Soup of Numbers", code: "soup_of_numbers", description: "Find numbers")
    @room = Room.create!(game: @game)
  end

  teardown do
    Player.where(room_id: @room.id).delete_all
    @room.delete
    @game.delete
  end

  test "the settings screen offers every option" do
    get edit_room_path(@room.code)
    assert_response :success
    assert_select "input[name='room[game_state][grid_size]']", 4
    assert_select "input[name='room[game_state][max_digits]']", 4
    assert_select "input[name='room[game_state][total_rounds]']", 3
    assert_select "input[name='room[game_state][round_time]']", 3
  end

  test "host and player screens render" do
    GameServices::SoupOfNumbers.new(@room).setup_game!

    get playing_room_path(@room.code)
    assert_response :success
    assert_select "[data-controller='soup-of-numbers-host']"

    post submit_join_path(@room.code), params: { nickname: "Ana" }
    get playing_room_path(@room.code)
    assert_response :success
    assert_select "[data-controller='soup-of-numbers-player']"
  end
end
