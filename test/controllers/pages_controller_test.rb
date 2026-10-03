require "test_helper"

class PagesControllerTest < ActionDispatch::IntegrationTest
  test "privacy, about and contact pages render with the footer" do
    { privacy_path => "Privacy Policy", about_path => "About Grouparty", contact_path => "Contact" }.each do |path, heading|
      get path
      assert_response :success
      assert_select "h1", heading
      assert_select "footer a[href=?]", privacy_path
    end
  end

  test "the privacy policy covers AdSense and the contact email" do
    get privacy_path
    assert_select "a[href=?]", "https://policies.google.com/technologies/partner-sites"
    assert_select "a[href=?]", "mailto:#{PagesController::CONTACT_EMAIL}"
  end

  test "the sitemap lists the new pages" do
    get sitemap_path
    [ about_url, contact_url, privacy_url ].each { |url| assert_includes response.body, url }
  end
end
