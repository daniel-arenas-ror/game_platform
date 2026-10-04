require "test_helper"

# In test/development each ad renders as a dashed placeholder (aside[aria-label=Advertisement]).
class AdPlacementTest < ActionDispatch::IntegrationTest
  AD = "aside[aria-label=Advertisement]".freeze

  setup do
    @game = Game.create!(name: "Soup of Numbers", code: "soup_of_numbers", description: "Find numbers")
    @room = Room.create!(game: @game)
  end

  teardown do
    Player.where(room_id: @room.id).delete_all
    @room.delete
    @game.delete
  end

  test "home, games, lobby and info pages show ads" do
    get root_path
    assert_select AD, 1

    get games_path
    assert_select AD, 1

    get room_path(@room.code)
    assert_select AD, 1

    [ about_path, contact_path, privacy_path ].each do |path|
      get path
      assert_select AD, 1
    end
  end

  test "settings and the join pages never show ads" do
    get find_room_path
    assert_select AD, 0

    get edit_room_path(@room.code)
    assert_select AD, 0

    get join_room_path(@room.code)
    assert_select AD, 0
  end

  test "a game screen only has the host's Game Over ad, and players get none" do
    GameServices::SoupOfNumbers.new(@room).setup_game!

    get playing_room_path(@room.code)
    assert_select "[data-soup-of-numbers-host-target=phaseGameOver] #{AD}", 1
    assert_select AD, 1

    post submit_join_path(@room.code), params: { nickname: "Ana" }
    get playing_room_path(@room.code)
    assert_select AD, 0
  end
end
