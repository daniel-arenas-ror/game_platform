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
      assert_select "footer svg[viewBox='0 0 1200 60']", 1 # the snowdrift
      assert_select "header a[href=?] svg.xmas-tree", christmas_path # the tree link
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
      assert_select "footer svg[viewBox='0 0 1200 60']", 0
      assert_select "header svg.xmas-tree", 0
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
      assert_select "[data-controller=christmas-jingle]", 1, "the TV plays the jingle"
    end
    with_christmas(false) do
      get playing_room_path(room.code)
      assert_select "[data-controller=christmas-jingle]", 0
    end
  ensure
    Event.where(room_id: room&.id).delete_all
    room&.delete
    game&.delete
  end

  test "a new room starts with the game's Christmas option only in Christmas mode" do
    game  = Game.create!(name: "Xmas Match #{SecureRandom.hex(2)}", code: "mind_match", description: "x")
    rooms = []
    [ true, false ].each do |on|
      with_christmas(on) { post rooms_path, params: { game_id: game.id } }
      rooms << Room.where(game_id: game.id).order_by(created_at: :desc).first
    end
    assert_equal "christmas", rooms.first.game_state["theme"]
    assert_nil rooms.last.game_state["theme"]
  ensure
    Event.where(:room_id.in => rooms.compact.map(&:id)).delete_all
    rooms&.compact&.each(&:delete)
    game&.delete
  end
end
