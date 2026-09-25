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

  test "should get sitemap" do
    get sitemap_url
    assert_response :success
    assert_includes response.body, "<loc>#{root_url}</loc>"
  end

  test "should get robots.txt pointing to the sitemap" do
    get robots_url
    assert_response :success
    assert_includes response.body, "Sitemap: #{sitemap_url}"
  end
end
