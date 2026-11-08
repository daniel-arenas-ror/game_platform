require "test_helper"

class GuessTheColorTest < ActiveSupport::TestCase
  Color = GameServices::GuessTheColor

  def rgb(r, g, b) = { "r" => r, "g" => g, "b" => b }

  test "the same colour is a perfect 1000, nothing picked is 0" do
    orange = rgb(230, 120, 40)
    assert_equal 1000, Color.calculate_score(orange, orange)
    assert_equal 0, Color.calculate_score(orange, nil)
  end

  test "scores follow what eyes see: a close shade beats a different colour" do
    orange = rgb(230, 120, 40)
    near   = Color.calculate_score(orange, rgb(225, 128, 50))
    red    = Color.calculate_score(orange, rgb(220, 40, 40))
    blue   = Color.calculate_score(orange, rgb(40, 80, 220))

    assert_operator near, :>=, Color::PERFECT_MATCH * 10, "a barely different shade counts as perfect"
    assert_operator near, :>, red
    assert_operator red, :>, blue
    assert_operator blue, :<, 50
  end

  test "match percent is points out of 10" do
    assert_equal 94, Color.match_percent(943)
    assert_equal 100, Color.match_percent(1000)
  end
end
