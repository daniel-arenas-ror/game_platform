require "test_helper"

class AnalyticsHelperTest < ActionView::TestCase
  test "queued events become gtag calls in production with a measurement ID" do
    flash[:analytics_events] = [ { "name" => "room_created", "params" => { "game_name" => "mind-match" } } ]

    define_singleton_method(:analytics_enabled?) { true } # production with a measurement ID

    assert_includes queued_analytics_events_tag, %(gtag('event', "room_created", {"game_name":"mind-match"});)
  end

  test "nothing outside production (the test env)" do
    flash[:analytics_events] = [ { "name" => "room_created", "params" => {} } ]
    assert_nil queued_analytics_events_tag
  end
end
