require "test_helper"

# Game rules of GameServices::BattleCity#tick!, run on a plain state hash (no database).
class BattleCityTest < ActiveSupport::TestCase
  Room = Struct.new(:players)

  setup do
    @service = GameServices::BattleCity.new(Room.new([]))
  end

  # Ana at (5,5) facing right with Beto right in front of her at (7,5); extra players far away.
  def state(kills_to_win:, extra: [])
    tanks = {
      "ana"  => { "x" => 5, "y" => 5, "direction" => "right", "alive" => true },
      "beto" => { "x" => 7, "y" => 5, "direction" => "left",  "alive" => true }
    }
    extra.each_with_index { |id, i| tanks[id] = { "x" => 20, "y" => 20 + i, "direction" => "up", "alive" => true } }
    {
      "status" => "playing", "tick" => 0, "map_cols" => 26, "map_rows" => 26,
      "walls" => {}, "bullets" => [], "base" => { "x" => 12, "y" => 24, "alive" => true },
      "tanks" => tanks,
      "tank_spawns" => tanks.transform_values { |t| { "x" => t["x"], "y" => t["y"] + 10 } },
      "scores" => tanks.keys.index_with(0),
      "kills_to_win" => kills_to_win
    }
  end

  def ana_shoots(state)
    @service.tick!(state, { "ana" => { "direction" => nil, "firing" => true } })
  end

  test "one kill doesn't end a game with a kill target; the tank comes back" do
    s = state(kills_to_win: 5)
    ana_shoots(s)

    assert_equal "playing", s["status"]
    assert_equal 1, s["scores"]["ana"]
    assert_not s["tanks"]["beto"]["alive"]

    GameServices::BattleCity::RESPAWN_TICKS.times { @service.tick!(s, {}) }
    assert s["tanks"]["beto"]["alive"], "Beto respawns"
    assert_equal "playing", s["status"]
  end

  test "a shot is reported even when its bullet hits in the same tick" do
    delta = ana_shoots(state(kills_to_win: 5))

    assert_equal [ "ana" ], delta["shots"]
    assert_empty delta["bullets"]
    assert_nil @service.tick!(state(kills_to_win: 5), {})["shots"]
  end

  test "breaking a brick says who broke it" do
    s = state(kills_to_win: 5)
    s["walls"] = { "7,5" => "brick" }
    s["tanks"]["beto"].merge!("x" => 20, "y" => 20)
    delta = ana_shoots(s)

    assert_equal [ "7,5" ], delta["walls_destroyed"]
    assert_equal [ "ana" ], delta["bricks_by"]
  end

  test "reaching the kill target wins" do
    s = state(kills_to_win: 1)
    ana_shoots(s)

    assert_equal "game_over", s["status"]
    assert_equal "kills_limit", s["game_over_reason"]
    assert_equal "ana", s["winner_id"]
  end

  test "base only: a destroyed player is out and the last tank standing wins" do
    s = state(kills_to_win: 0)
    ana_shoots(s)

    assert_equal "game_over", s["status"]
    assert_equal "last_tank_standing", s["game_over_reason"]
    assert_equal "ana", s["winner_id"]
    assert_nil s["tanks"]["beto"]["respawn_tick"]
  end

  test "base only: the game goes on while two players are still driving" do
    s = state(kills_to_win: 0, extra: [ "caro" ])
    ana_shoots(s)

    assert_equal "playing", s["status"]
    (GameServices::BattleCity::RESPAWN_TICKS + 5).times { @service.tick!(s, {}) }
    assert_not s["tanks"]["beto"]["alive"], "Beto stays out"
    assert_equal "playing", s["status"]
  end
end
