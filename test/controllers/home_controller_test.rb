require "test_helper"

class HomeControllerTest < ActionDispatch::IntegrationTest
  test "should get index with SEO tags" do
    get root_url
    assert_response :success
    assert_select "title", /Grouparty/
    assert_select "meta[name=description]"
    assert_select "link[rel=canonical]"
    assert_select "meta[property='og:image']"
    assert_select "script[type='application/ld+json']"
  end

  test "home links to the games and join pages" do
    get root_url
    assert_select "a[href=?]", games_path, minimum: 1
    assert_select "a[href=?]", find_room_path, minimum: 1
    assert_select "nav[aria-label=Main] a[aria-current=page]", "Home"
  end

  test "home explains the idea and suggests games per setting" do
    game = Game.create!(name: "Mind Match", code: "mind_match", description: "Words")
    get root_url
    assert_select "h1", /fun touch/
    assert_select "h2", "Made for any room"
    assert_select "dt", "Wake up your brain"
    assert_select "a[href=?]", games_path, text: "Start a game", count: 2
    assert_select "a[href=?]", find_room_path, text: "Join a game", count: 2
    assert_select "img[src=?]", "/games/mind_match/instructions.png"
  ensure
    game&.delete
  end

  test "should get the games page" do
    get games_url
    assert_response :success
    assert_select "h1", "Pick a game"
    assert_select "title", /Games/
  end

  test "should get sitemap" do
    get sitemap_url
    assert_response :success
    assert_includes response.body, "<loc>#{root_url}</loc>"
    assert_includes response.body, "<loc>#{games_url}</loc>"
    assert_includes response.body, "<loc>#{find_room_url}</loc>"
  end

  test "should get robots.txt pointing to the sitemap" do
    get robots_url
    assert_response :success
    assert_includes response.body, "Sitemap: #{sitemap_url}"
  end
end
