require "test_helper"

class Games::TugOfWarChannelTest < ActionCable::Channel::TestCase
  Tug = GameServices::TugOfWar

  setup do
    @game = Game.create!(name: "Tug of War", code: "tug_of_war", description: "Pull")
    @room = Room.create!(game: @game, game_state: { "rope_length" => "short", "time_limit" => "0", "total_rounds" => "3" })
    @ana, @beto, @caro, @dani = %w[Ana Beto Caro Dani].map { |n| @room.players.create!(nickname: n) }
    Tug.new(@room).setup_game!
    teams = { @ana => "red", @beto => "red", @caro => "blue", @dani => "blue" }.to_h { |p, t| [ p.id.to_s, t ] }
    @room.atomic_set("game_state.teams" => teams)
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
    with_constants(Games::TugOfWarChannel, COUNTDOWN_DURATION: 0.1, ROUND_OVER_DURATION: 5, GRACE_PERIOD: 0,
                   EARLY_END_DELAY: 0, POLL_INTERVAL: 0.02, &)
  end

  def room_stream = "tug_of_war_room_#{@room.code}"
  def player_stream(player) = "#{room_stream}_player_#{player.id}"
  def messages = broadcasts(room_stream).map { JSON.parse(_1) }
  def phases = messages.filter_map { _1.dig("state", "phase") }
  def state = @room.reload.game_state
  def svc = Tug.new(Room.find(@room.id))

  def problem(player) = state["problems"][player.id.to_s]
  def right!(player) = svc.answer!(player.id, problem(player)["id"], problem(player)["answer"])

  def wait_until(seconds = 8)
    Timeout.timeout(seconds) { sleep 0.02 until yield }
  end

  def pull!
    svc.start_round!(1, 3)
    svc.start_pulling!
  end

  test "a whole best of three: teams screen, rounds end when the rope reaches an end, the host skips" do
    fast do
      subscribe(room_code: @room.code, player_id: "")
      perform :start_game_loop
      wait_until { phases.include?("teams") }
      sleep 0.1
      assert_equal [ "teams" ], phases.uniq

      perform :start_pulling
      2.times do |round|
        wait_until { phases.count("pulling") > round }
        10.times { right!(@caro) }
        wait_until { phases.count("round_over") > round }
        perform :skip
      end

      wait_until { phases.include?("game_over") }
      assert_equal %w[teams] + %w[countdown pulling round_over] * 2 + %w[game_over], phases.chunk_while { _1 == _2 }.map(&:first)
      last = messages.last["state"]
      assert_equal [ "blue", { "red" => 0, "blue" => 2 } ], last.values_at("champion", "wins")
      assert_equal [ @caro.id.to_s, @dani.id.to_s ].sort, last["winners"].sort
      assert_equal [ @caro.id.to_s ], last["mvp"]
      assert_equal "finished", @room.reload.status
    end
  end

  test "each phone gets its own problem on its own stream, without the answer" do
    fast do
      subscribe(room_code: @room.code, player_id: "")
      perform :start_game_loop
      perform :start_pulling
      wait_until { phases.include?("pulling") }

      sent = broadcasts(player_stream(@ana)).map { JSON.parse(_1) }.last
      assert_equal [ "problem", 1, problem(@ana)["id"] ], [ sent["action"], sent["round"], sent.dig("problem", "id") ]
      assert_not sent["problem"].key?("answer")
      assert(messages.none? { _1.to_s.include?(problem(@ana)["id"]) })
      perform :restart_game # stops the loop
    end
  end

  test "a correct answer comes back with the next problem and everyone sees the pull" do
    pull!
    subscribe(room_code: @room.code, player_id: @ana.id.to_s)
    old = problem(@ana)
    perform :answer, "problem_id" => old["id"], "value" => old["answer"].to_s, "id" => 7

    result = transmissions.last
    assert_equal [ "answer_result", 7, "correct" ], result.values_at("action", "id", "result")
    assert_equal problem(@ana)["id"], result.dig("problem", "id")
    pull = messages.last
    assert_equal [ "pull", @ana.id.to_s, "red", -10.0, 1 ], pull.values_at("action", "player_id", "team", "position", "pulls")
    assert_not pull.key?("problem")
  end

  test "a wrong answer freezes the phone and everyone sees it; a reload keeps it frozen" do
    pull!
    subscribe(room_code: @room.code, player_id: @beto.id.to_s)
    old = problem(@beto)
    perform :answer, "problem_id" => old["id"], "value" => (old["answer"] + 1).to_s, "id" => 1

    assert_equal [ "wrong", old["answer"], 2 ], transmissions.last.values_at("result", "answer", "seconds")
    assert_equal [ "frozen", @beto.id.to_s ], messages.last.values_at("action", "player_id")

    perform :sync
    shown = transmissions.last["state"]
    assert_in_delta 2, shown["frozen_seconds"], 0.5
    assert_equal problem(@beto)["id"], shown.dig("problem", "id")
    assert_equal "red", shown["team"]
  end

  test "the host moves players and shuffles; everyone hears the new teams" do
    subscribe(room_code: @room.code, player_id: "")
    perform :move_player, "player_id" => @ana.id.to_s
    assert_equal "blue", state["teams"][@ana.id.to_s]
    sent = messages.last
    assert_equal [ "teams", "blue", { "red" => 1, "blue" => 3 } ], [ sent["action"], sent["teams"][@ana.id.to_s], sent["team_sizes"] ]

    perform :move_player, "player_id" => @ana.id.to_s, "team" => "red"
    assert_equal "red", state["teams"][@ana.id.to_s]

    perform :shuffle_teams
    assert_equal({ "red" => 2, "blue" => 2 }, state["teams"].values.tally)
    assert_equal 3, messages.count { _1["action"] == "teams" }
  end

  test "a player who joins late is put on a team and the screens hear it" do
    eva = @room.players.create!(nickname: "Eva")
    @room.atomic_set("game_state.teams.#{@ana.id}" => "blue")
    subscribe(room_code: @room.code, player_id: eva.id.to_s)

    assert_equal "red", state["teams"][eva.id.to_s]
    assert_equal [ "teams", "Eva" ], messages.last.then { [ _1["action"], _1["nicknames"][eva.id.to_s] ] }
    assert_equal "red", transmissions.last.dig("state", "team")
  end

  test "players can't run the loop, change teams, start, skip or restart" do
    subscribe(room_code: @room.code, player_id: @ana.id.to_s)
    perform :start_game_loop
    perform :move_player, "player_id" => @beto.id.to_s
    perform :shuffle_teams
    perform :start_pulling
    perform :skip
    perform :restart_game
    s = state
    assert_nil s["loop_id"]
    assert_nil s["start"]
    assert_equal "red", s["teams"][@beto.id.to_s]
    assert_empty messages
  end

  test "answers outside the pulling do nothing" do
    subscribe(room_code: @room.code, player_id: @ana.id.to_s)
    perform :answer, "problem_id" => "x", "value" => "1", "id" => 1
    assert_equal "closed", transmissions.last["result"]
    assert_empty messages
  end

  test "with a time limit the round ends when it runs out; the rope's side wins" do
    @room.atomic_set("game_state.time_limit" => 1, "game_state.total_rounds" => 1)
    fast do
      subscribe(room_code: @room.code, player_id: "")
      perform :start_game_loop
      perform :start_pulling
      wait_until { phases.include?("pulling") }
      right!(@ana)
      wait_until { phases.include?("round_over") }

      assert_equal "red", messages.reverse.find { _1.dig("state", "phase") == "round_over" }.dig("state", "winner")
      perform :skip
      wait_until { phases.include?("game_over") }
      assert_equal "red", messages.last.dig("state", "champion")
    end
  end

  test "one loop per game; Play Again stops it" do
    fast do
      subscribe(room_code: @room.code, player_id: "")
      perform :start_game_loop
      first = @room.reload.game_state["loop_id"]
      perform :start_game_loop
      assert_equal first, @room.reload.game_state["loop_id"]

      perform :restart_game
      assert_equal [ "teams", nil ], @room.reload.game_state.values_at("phase", "loop_id")
      perform :start_pulling
      sleep 0.3
      assert_equal "teams", @room.reload.game_state["phase"]
    end
  end
end
