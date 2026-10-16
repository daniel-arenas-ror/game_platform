require "test_helper"

class Games::MonsterMashChannelTest < ActionCable::Channel::TestCase
  Mash = GameServices::MonsterMash

  setup do
    @game = Game.create!(name: "Monster Mash", code: "monster_mash", description: "Draw")
    @room = Room.create!(game: @game, game_state: {})
    @ana, @beto, @caro = %w[Ana Beto Caro].map { |n| @room.players.create!(nickname: n) }
    Mash.new(@room).setup_game!
  end

  teardown do
    MonsterMash::Drawing.where(room_id: @room.id).delete_all
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
    with_constants(Games::MonsterMashChannel, THEME_DURATION: 0.1, PASS_DURATION: 0.1, REVEAL_EACH: 5, VOTE_DURATION: 5,
                   RESULTS_DURATION: 5, GRACE_PERIOD: 0, EARLY_END_DELAY: 0, POLL_INTERVAL: 0.02, &)
  end

  def room_stream = "monster_mash_room_#{@room.code}"
  def host_stream = "monster_mash_room_#{@room.code}_host"
  def player_stream(player) = "monster_mash_room_#{@room.code}_player_#{player.id}"
  def messages(stream) = broadcasts(stream).map { JSON.parse(_1) }
  def phases = messages(host_stream).filter_map { _1.dig("state", "phase") }
  def svc = Mash.new(Room.find(@room.id))
  def order = @room.reload.game_state["order"]
  def stroke(id) = { "id" => id, "color" => "#111827", "size" => 10, "points" => [ [ 0.5, 0.5 ], [ 0.5, 0.95 ] ] }

  def wait_until(seconds = 8)
    Timeout.timeout(seconds) { sleep 0.02 until yield }
  end

  test "a whole game: three rounds that end once everyone is done, the reveal, the vote, the gallery" do
    fast do
      subscribe(room_code: @room.code, player_id: "")
      perform :start_game_loop

      3.times do |round|
        wait_until { messages(host_stream).count { _1.dig("state", "phase") == "drawing" } > round }
        order.each_with_index { |pid, i| svc.save_stroke!(pid, stroke(i + 1)); svc.done!(pid) }
      end

      # The host skips through the three monsters.
      3.times do |i|
        wait_until { messages(room_stream).count { _1["action"] == "monster" } > i }
        perform :skip
      end

      wait_until { phases.include?("vote") }
      ids = order
      svc.vote!(ids[0], 1)
      svc.vote!(ids[1], 0)
      svc.vote!(ids[2], 1)

      wait_until { phases.include?("results") }
      perform :skip
      wait_until { messages(host_stream).any? { _1["action"] == "gallery" } }

      assert_equal %w[theme drawing passing drawing passing drawing reveal vote results game_over], phases.chunk_while { _1 == _2 }.map(&:first)
      revealed = messages(room_stream).select { _1["action"] == "monster" }.map { _1["monster"] }
      assert_equal [ 0, 1, 2 ], revealed.map { _1["index"] }
      assert(revealed.all? { |m| m["parts"].values.all? { _1.size == 1 } })
      assert_equal [ 1 ], messages(host_stream).find { _1.dig("state", "phase") == "results" }.dig("state", "results", "top")
      assert_equal 3, messages(host_stream).find { _1["action"] == "gallery" }["monsters"].size
      assert_equal "finished", @room.reload.status
    end
  end

  test "strokes from a phone are cleaned and saved, never sent to the TV" do
    svc.start_round!(0, 60)
    subscribe(room_code: @room.code, player_id: @ana.id.to_s)
    perform :stroke_end, "id" => 1, "points" => [ [ 0.2, 2.0 ], [ -1, 0.5 ] ], "color" => "#111827", "size" => 10
    perform :stroke_end, "id" => 2, "points" => [ [ 0.2, 0.2 ] ], "color" => "#123456", "size" => 10 # not in the palette

    drawing = MonsterMash::Drawing.where(room_id: @room.id, player_id: @ana.id.to_s).first
    assert_equal [ [ [ 0.2, 1.0 ], [ 0.0, 0.5 ] ] ], drawing.strokes.map { _1["points"] }
    assert_empty broadcasts(host_stream)
  end

  test "Done is confirmed to the phone and everyone sees who is done" do
    svc.start_round!(0, 60)
    subscribe(room_code: @room.code, player_id: @ana.id.to_s)
    perform :done

    assert_equal "done_ok", transmissions.last["action"]
    assert_equal [ @ana.id.to_s ], messages(room_stream).last["ids"]
  end

  test "a phone that reloads mid-round gets its task and its drawing so far" do
    svc.start_round!(0, 60)
    svc.save_stroke!(@beto.id, stroke(7))
    subscribe(room_code: @room.code, player_id: @beto.id.to_s)

    task = transmissions.find { _1["action"] == "state" }.dig("state", "assignment")
    assert_equal "head", task["part"]
    assert_equal [ 7 ], task["strokes"].map { _1["id"] }
  end

  test "a phone that joins during the reveal gets the monster on show" do
    3.times { |round| svc.start_round!(round, 60) }
    s = svc
    s.start_reveal!
    s.reveal!(1)

    subscribe(room_code: @room.code, player_id: @caro.id.to_s)
    assert_equal 1, transmissions.find { _1["action"] == "monster" }.dig("monster", "index")
  end

  test "votes come back to the voter and the room sees who has voted" do
    svc.start_vote!(30)
    subscribe(room_code: @room.code, player_id: @ana.id.to_s)
    mine = order.index(@ana.id.to_s)
    perform :vote, "index" => (mine + 1) % 3

    assert_equal [ "voted", (mine + 1) % 3 ], transmissions.last.values_at("action", "index")
    assert_equal [ @ana.id.to_s ], messages(room_stream).last["ids"]
  end

  test "players can't run the loop, skip or restart" do
    subscribe(room_code: @room.code, player_id: @ana.id.to_s)
    perform :start_game_loop
    perform :skip
    perform :restart_game
    assert_nil @room.reload.game_state["loop_id"]
    assert_empty messages(room_stream)
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
