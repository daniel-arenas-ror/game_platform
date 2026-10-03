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

  test "home, lobby and info pages show ads" do
    get root_path
    assert_select AD, 2

    get room_path(@room.code)
    assert_select AD, 1

    [ about_path, contact_path, privacy_path ].each do |path|
      get path
      assert_select AD, 1
    end
  end

  test "game screens, settings and the join form never show ads" do
    get edit_room_path(@room.code)
    assert_select AD, 0

    get join_room_path(@room.code)
    assert_select AD, 0

    GameServices::SoupOfNumbers.new(@room).setup_game!
    get playing_room_path(@room.code)
    assert_select AD, 0
    assert_no_match "adsbygoogle", response.body
  end
end
