require "test_helper"

# A 406 on Start game or the join link is a dead end for anyone on an old device (and we suspected
# it hurt the AdSense review), so old browsers get every page, with a banner on room screens.
class OldBrowserTest < ActionDispatch::IntegrationTest
  OLD_CHROME = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) " \
               "Chrome/109.0.0.0 Safari/537.36".freeze
  MODERN_CHROME = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) " \
                  "Chrome/140.0.0.0 Safari/537.36".freeze
  BANNER = "p[role=status]".freeze

  setup do
    @game = Game.create!(name: "Soup of Numbers", code: "soup_of_numbers", description: "Find numbers")
  end

  teardown do
    Room.where(game_id: @game.id).each { |room| Player.where(room_id: room.id).delete_all }
    Room.where(game_id: @game.id).delete_all
    @game.delete
  end

  test "an old browser can start a game and open the join link, with an update banner" do
    old = { "User-Agent" => OLD_CHROME }

    post rooms_path(game_id: @game.id), headers: old
    assert_response :redirect
    room = Room.where(game_id: @game.id).last

    [ edit_room_path(room.code), room_path(room.code), join_room_path(room.code) ].each do |path|
      get path, headers: old
      assert_response :success
      assert_select BANNER, /out of date/
    end
  end

  test "modern browsers and public pages get no banner" do
    room = Room.create!(game: @game)

    get join_room_path(room.code), headers: { "User-Agent" => MODERN_CHROME }
    assert_response :success
    assert_select BANNER, 0

    get root_path, headers: { "User-Agent" => OLD_CHROME }
    assert_response :success
    assert_select BANNER, 0
  end
end
