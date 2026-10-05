require "test_helper"

class GamesControllerTest < ActionDispatch::IntegrationTest
  setup do
    @game = Game.create!(name: "Soup of Numbers", code: "soup_of_numbers", description: "Find numbers",
                         slug: "soup-of-numbers-#{SecureRandom.hex(3)}")
  end

  teardown { @game.delete }

  test "game page lives at /games/:slug and starts a room" do
    get game_path(@game)
    assert_equal "/games/#{@game.slug}", path
    assert_response :success
    assert_select "h1", "Soup of Numbers"
    assert_select "title", /Soup of Numbers/
    assert_select "nav[aria-label=Breadcrumb] a[href=?]", games_path
    assert_select "form[action=?] button", rooms_path(game_id: @game.id), text: "Start game"
    assert_select "aside[aria-label=Advertisement]", 1
  end

  test "unknown slug is a 404" do
    get game_path("no-such-game")
    assert_response :not_found
  end

  test "catalog cards link to the game page, except in change-game mode" do
    get games_path
    assert_select "a[href=?]", game_path(@game)

    room = Room.create!(game: @game)
    get games_path(room: room.code)
    assert_select "a[href=?]", game_path(@game), 0
  ensure
    room&.delete
  end

  test "slug defaults to the parameterized name" do
    game = Game.new(name: "Mind Match", code: "mind_match")
    game.validate
    assert_equal "mind-match", game.slug
  end

  test "every seeded game has its YAML file with a unique, valid slug" do
    files = Dir[Rails.root.join("db/seeds/games/*.yml")]
    slugs = files.map { |f| YAML.load_file(f).fetch("slug") }

    assert_equal 10, files.size
    assert_equal slugs.uniq, slugs
    assert(slugs.all? { |s| s.match?(/\A[a-z0-9]+(?:-[a-z0-9]+)*\z/) })
    assert_includes slugs, "how-to-be-a-billionaire"
  end
end
