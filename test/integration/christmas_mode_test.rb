require "test_helper"

# Christmas mode (SiteSetting#christmas, the admin switch): Santa hat, snow and lights on the public
# pages only. The switch is stubbed here, since tests share one database in parallel.
class ChristmasModeTest < ActionDispatch::IntegrationTest
  def with_christmas(on)
    original = SiteSetting.method(:christmas?)
    SiteSetting.define_singleton_method(:christmas?) { on }
    yield
  ensure
    SiteSetting.define_singleton_method(:christmas?, original)
  end

  test "on: the public pages get the hat, the Christmas icon, the lights and the snow" do
    with_christmas(true) do
      get root_path
      assert_response :success
      assert_select "header .xmas-lights"
      assert_select "header svg g[transform]", minimum: 1 # the hat on the logo
      assert_select "link[rel=icon][href^='/icon-christmas.svg']"
      assert_select "link[rel=icon][href^='/favicon.ico']", 0
      assert_select "[data-controller=snow]", 1
      assert_select "title", /Christmas/
      assert_select "a[href=?]", christmas_path, text: /Christmas games for the whole group/
    end
  end

  test "off: none of it" do
    with_christmas(false) do
      get root_path
      assert_select ".xmas-lights", 0
      assert_select "[data-controller=snow]", 0
      assert_select "link[rel=icon][href^='/icon-christmas.svg']", 0
      assert_select "title", { text: /Christmas/, count: 0 }
    end
  end

  test "never during a game" do
    game = Game.create!(name: "Xmas #{SecureRandom.hex(2)}", code: "color_chain", description: "x")
    room = Room.create!(game: game, status: "playing")
    GameServices::ColorChain.new(room).setup_game!
    with_christmas(true) do
      get playing_room_path(room.code)
      assert_response :success
      assert_select "[data-controller=snow]", 0
      assert_select ".xmas-lights", 0
    end
  ensure
    Event.where(room_id: room&.id).delete_all
    room&.delete
    game&.delete
  end
end
