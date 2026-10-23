require "test_helper"

class Games::CharacterHuntChannelTest < ActionCable::Channel::TestCase
  Hunt  = GameServices::CharacterHunt
  Crowd = GameServices::CharacterHunt::Crowd

  setup do
    @game = Game.create!(name: "Character Hunt", code: "character_hunt", description: "Find them")
    @room = Room.create!(game: @game, game_state: { "total_rounds" => "3", "round_time" => "60", "difficulty" => "easy" })
    @ana, @beto, @caro, @dani = %w[Ana Beto Caro Dani].map { |n| @room.players.create!(nickname: n) }
    Hunt.new(@room).setup_game!
  end

  teardown do
    Player.where(room_id: @room.id).delete_all
    Event.where(room_id: @room.id).delete_all
    @room.delete
    @game.delete
  end

  # Shrinks the game's timers for one test.
  def with_constants(mod, **values)
    old = values.to_h { |name, _| [ name, mod.const_get(name) ] }
    silence_warnings { values.each { |name, value| mod.const_set(name, value) } }
    yield
  ensure
    silence_warnings { old.each { |name, value| mod.const_set(name, value) } }
  end

  def fast(&)
    with_constants(Games::CharacterHuntChannel, INTRO_DURATION: 0.1, REVEAL_DURATION: 5, GRACE_PERIOD: 0,
                   EARLY_END_DELAY: 0, POLL_INTERVAL: 0.02, &)
  end

  def room_stream = "character_hunt_room_#{@room.code}"
  def messages = broadcasts(room_stream).map { JSON.parse(_1) }
  def phases = messages.filter_map { _1.dig("state", "phase") }
  def state = @room.reload.game_state

  # Where a finger would tap a character.
  def spot(index)
    c = state["scene"]["characters"][index]
    { "x" => c["x"], "y" => c["y"] - c["h"] / 2 }
  end

  def target_spot = spot(state["target_index"])

  def find!(player)
    Hunt.new(Room.find(@room.id)).tap!(player.id, *target_spot.values)
  end

  def wait_until(seconds = 8)
    Timeout.timeout(seconds) { sleep 0.02 until yield }
  end

  test "a whole game: each round ends once three have found the target, the host skips the reveal" do
    fast do
      subscribe(room_code: @room.code, player_id: "")
      perform :start_game_loop

      3.times do |round|
        wait_until { phases.count("search") > round }
        [ @beto, @ana, @caro ].each { find!(_1) }
        wait_until { phases.count("reveal") > round }
        perform :skip
      end

      wait_until { phases.include?("game_over") }
      assert_equal %w[intro search reveal] * 3 + %w[game_over], phases.chunk_while { _1 == _2 }.map(&:first)
      assert_equal [ 1, 2, 3 ], messages.select { _1.dig("state", "phase") == "intro" }.map { _1.dig("state", "round") }

      last = messages.last["state"]
      assert_equal [ @beto.id.to_s ], last["winners"]
      assert_equal({ @beto.id.to_s => 9, @ana.id.to_s => 6, @caro.id.to_s => 3, @dani.id.to_s => 0 }, last["scores"])
      assert_equal "finished", @room.reload.status
    end
  end

  test "the search shows the scene and who to find, but not where they are" do
    fast do
      subscribe(room_code: @room.code, player_id: "")
      perform :start_game_loop
      wait_until { phases.include?("search") }

      shown = messages.find { _1.dig("state", "phase") == "search" }["state"]
      assert_equal 60, shown["scene"]["characters"].size
      assert shown["target"]
      assert_not shown.key?("target_index")
      perform :restart_game # stops the loop
    end
  end

  test "a find comes back to the phone and everyone hears it" do
    Hunt.new(@room).start_round!(1, 5)
    Hunt.new(@room).start_search!
    subscribe(room_code: @room.code, player_id: @ana.id.to_s)
    perform :tap, target_spot.merge("id" => 7)

    assert_equal [ "tap_result", 7, "found", 1, 3 ], transmissions.last.values_at("action", "id", "result", "place", "points")
    found = messages.last
    assert_equal [ "found", @ana.id.to_s, 1, 3 ], found.values_at("action", "player_id", "place", "points")
    assert_equal 3, found["scores"][@ana.id.to_s]
  end

  test "a wrong tap freezes the phone and everyone sees it; a reload keeps it frozen" do
    Hunt.new(@room).start_round!(1, 5)
    Hunt.new(@room).start_search!
    s     = state["scene"]
    other = (0...s["characters"].size).find { |i| i != state["target_index"] && Crowd.hit(s, *spot(i).values) == i }

    subscribe(room_code: @room.code, player_id: @beto.id.to_s)
    perform :tap, spot(other).merge("id" => 1)
    result = transmissions.last
    assert_equal [ "wrong", other ], result.values_at("result", "index")
    assert_equal [ "frozen", @beto.id.to_s ], messages.last.values_at("action", "player_id")

    perform :sync
    assert_in_delta result["seconds"], transmissions.last.dig("state", "frozen_seconds"), 0.5
  end

  test "taps outside the search do nothing" do
    subscribe(room_code: @room.code, player_id: @ana.id.to_s)
    perform :tap, "x" => 0.5, "y" => 0.5, "id" => 1
    assert_equal "closed", transmissions.last["result"]
    assert_empty messages
  end

  test "players can't run the loop, skip or restart" do
    subscribe(room_code: @room.code, player_id: @ana.id.to_s)
    perform :start_game_loop
    perform :skip
    perform :restart_game
    assert_nil @room.reload.game_state["loop_id"]
    assert_empty messages
  end

  test "one loop per game; Play Again stops it" do
    fast do
      subscribe(room_code: @room.code, player_id: "")
      perform :start_game_loop
      first = @room.reload.game_state["loop_id"]
      perform :start_game_loop
      assert_equal first, @room.reload.game_state["loop_id"]

      perform :restart_game
      assert_equal [ "waiting", nil ], @room.reload.game_state.values_at("phase", "loop_id")
      sleep 0.3
      assert_equal "waiting", @room.reload.game_state["phase"]
    end
  end
end
