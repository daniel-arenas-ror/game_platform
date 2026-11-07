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

  test "a tank right in front of the barrel is hit; so is a brick" do
    s = state(kills_to_win: 5)
    s["tanks"]["beto"]["x"] = 6
    ana_shoots(s)
    assert_not s["tanks"]["beto"]["alive"]
    assert_equal 1, s["scores"]["ana"]

    s = state(kills_to_win: 5)
    s["walls"] = { "6,5" => "brick" }
    delta = ana_shoots(s)
    assert_equal [ "6,5" ], delta["walls_destroyed"]
    assert_equal [ "ana" ], delta["shots"]
  end

  test "a player comes back at a free spawn point, shielded for 3 seconds" do
    s = state(kills_to_win: 5)
    s["spawn_points"] = [ [ 2, 2 ], [ 23, 2 ] ]
    s["tanks"]["ana"].merge!("x" => 23, "y" => 2) # one point is taken
    s["tanks"]["ana"]["direction"] = "down"
    s["tanks"]["beto"].merge!("alive" => false, "respawn_tick" => 1)

    delta = @service.tick!(s, {})
    beto  = s["tanks"]["beto"]
    assert beto["alive"]
    assert_equal [ 2, 2 ], [ beto["x"], beto["y"] ]
    assert_equal 1 + GameServices::BattleCity::SHIELD_TICKS, beto["shield_until"]
    assert delta["tanks"]["beto"]["shield_until"], "the TV gets the shield to flicker the tank"

    GameServices::BattleCity::SHIELD_TICKS.times { delta = @service.tick!(s, {}) }
    assert_nil beto["shield_until"]
    assert_nil delta["tanks"]["beto"]["shield_until"], "the TV hears the shield is over"
  end

  test "a shield stops a bullet, and firing ends your own shield" do
    s = state(kills_to_win: 5)
    s["tanks"]["beto"]["shield_until"] = 100
    ana_shoots(s)
    assert s["tanks"]["beto"]["alive"]
    assert_equal 0, s["scores"]["ana"]
    assert_empty s["bullets"]

    delta = @service.tick!(s, { "beto" => { "direction" => nil, "firing" => true } })
    assert_nil s["tanks"]["beto"]["shield_until"]
    assert delta["tanks"].key?("beto")
  end

  test "the 9 spawn points and 3 bots each get their own free cell, never a wall" do
    preset = BattleCity::MapPreset.new(cols: 26, rows: 26, base_x: 12, base_y: 24)
    walls  = { "12,2" => "brick", "12,12" => "steel", "2,12" => "trees" }
    spawns = @service.send(:spawn_cells, walls, preset, 3)
    cells  = spawns[:players] + spawns[:bots]

    assert_equal 12, cells.uniq.size
    cells.each do |x, y|
      assert_not walls.key?("#{x},#{y}"), "#{x},#{y} is a wall"
      assert x.between?(1, 24) && y.between?(1, 24), "#{x},#{y} is on the border"
    end
    assert_equal 9, spawns[:players].size
    assert_equal [ 2, 2 ], spawns[:players].first, "a free spot is kept"
    spawns[:players].zip(GameServices::BattleCity::SPAWN_SPOTS).each do |(x, y), (sx, sy)|
      assert_operator (x - sx).abs + (y - sy).abs, :<=, 1, "a walled spot moves to the next cell"
    end
  end

  test "the first 8 players get a tank and a colour each; a 9th watches" do
    game    = Game.create!(name: "Battle City", code: "battle_city", description: "x")
    preset  = BattleCity::MapPreset.create!(name: "test-#{SecureRandom.hex(3)}", base_x: 12, base_y: 24)
    room    = ::Room.create!(game: game, game_state: { "map_preset" => preset.name })
    players = 9.times.map { |i| room.players.create!(nickname: "P#{i}") }

    GameServices::BattleCity.new(room).setup_game!
    tanks = room.reload.game_state["tanks"]

    assert_equal players.first(8).map { _1.id.to_s }.sort, tanks.keys.sort
    assert_equal GameServices::BattleCity::TANK_COLORS.sort, tanks.values.map { _1["color"] }.sort
    assert_equal 8, tanks.values.map { [ _1["x"], _1["y"] ] }.uniq.size, "each on their own spot"
  ensure
    Player.where(room_id: room&.id).delete_all
    Event.where(room_id: room&.id).delete_all
    room&.delete
    preset&.delete
    game&.delete
  end
end
