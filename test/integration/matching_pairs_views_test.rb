require "test_helper"

class MatchingPairsViewsTest < ActionDispatch::IntegrationTest
  setup do
    @game = Game.create!(name: "Matching Pairs", code: "matching_pairs", description: "Find pairs")
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
    assert_select "input[name='room[game_state][grid]']", 4
    assert_select "input[name='room[game_state][category]']", 5
    assert_select "input[name='room[game_state][round_time]']", 4
    assert_select "input[name='room[game_state][total_rounds]']", 4
    assert_select "input[name='room[game_state][total_rounds]'][value='1'][checked]"
  end

  test "host and player screens render" do
    GameServices::MatchingPairs.new(@room).setup_game!

    get playing_room_path(@room.code)
    assert_response :success
    assert_select "[data-controller='matching-pairs-host']"

    post submit_join_path(@room.code), params: { nickname: "Ana" }
    get playing_room_path(@room.code)
    assert_response :success
    assert_select "[data-controller='matching-pairs-player'] [data-matching-pairs-player-target=board]"
  end
end
