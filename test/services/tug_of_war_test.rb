require "test_helper"

class TugOfWarTest < ActiveSupport::TestCase
  Tug      = GameServices::TugOfWar
  Problems = GameServices::TugOfWar::Problems

  setup do
    @game = Game.create!(name: "Tug of War", code: "tug_of_war", description: "Pull")
    @room = Room.create!(game: @game, game_state: { "difficulty" => "medium", "answer_mode" => "choice",
                                                    "rope_length" => "short", "time_limit" => "60", "total_rounds" => "3" })
    @players = %w[Ana Beto Caro Dani].map { |n| @room.players.create!(nickname: n) }
    Tug.new(@room).setup_game!
  end

  teardown do
    # Only this test's records: tests run in parallel against one database.
    Player.where(room_id: @room.id).delete_all
    Event.where(room_id: @room.id).delete_all
    @room.delete
    @game.delete
  end

  # Each player's channel loads its own copy of the room.
  def svc = Tug.new(Room.find(@room.id))
  def state = @room.reload.game_state
  def pid(player) = player.id.to_s
  def team_of(player) = state["teams"][pid(player)]
  def on(team) = @players.select { |p| team_of(p) == team }

  def pull!(round = 1)
    svc.start_round!(round, 3)
    svc.start_pulling!
  end

  def problem(player) = state["problems"][pid(player)]
  def right!(player) = svc.answer!(pid(player), problem(player)["id"], problem(player)["answer"])
  def wrong!(player) = svc.answer!(pid(player), problem(player)["id"], problem(player)["answer"] + 1)

  # Two players per team, so every pull is 100 / (5 × 2) = 10.
  def set_teams!(red, blue)
    teams = red.to_h { |p| [ pid(p), "red" ] }.merge(blue.to_h { |p| [ pid(p), "blue" ] })
    @room.atomic_set("game_state.teams" => teams)
  end

  # ── Setup ────────────────────────────────────────────────────────────────

  test "setup reads the settings and splits the players into two even teams" do
    s = state
    assert_equal [ "teams", 0, 3, 60, "medium", "choice", "short" ],
                 s.values_at("phase", "round", "total_rounds", "time_limit", "difficulty", "answer_mode", "rope_length")
    assert_equal @players.map { pid(_1) }.sort, s["teams"].keys.sort
    assert_equal({ "red" => 2, "blue" => 2 }, s["teams"].values.tally)
    assert_equal 0, s["position"]
  end

  test "bad settings fall back to the defaults; no time limit is a choice" do
    @room.update!(game_state: { "difficulty" => "insane", "answer_mode" => "telepathy", "rope_length" => "huge",
                                "time_limit" => "7", "total_rounds" => "2" })
    Tug.new(@room).setup_game!
    assert_equal [ "easy", "type", "normal", 120, 1 ],
                 state.values_at("difficulty", "answer_mode", "rope_length", "time_limit", "total_rounds")

    @room.update!(game_state: { "time_limit" => "0" })
    Tug.new(@room).setup_game!
    assert_equal 0, state["time_limit"]
  end

  test "an odd number of players splits as evenly as it can" do
    assert_equal [ 2, 3 ], Tug.split(%w[a b c d e]).values.tally.values.sort
  end

  # ── Problems ─────────────────────────────────────────────────────────────

  test "problems have whole answers that match their text" do
    Problems::DIFFICULTIES.each do |difficulty|
      200.times do
        p = Problems.generate(difficulty, "type")
        assert_kind_of Integer, p["answer"]
        assert_operator p["answer"], :>=, 0
        assert_equal p["answer"], eval(p["text"].tr("×÷−", "*/-")), p["text"] # rubocop:disable Security/Eval
        assert_not p.key?("choices")
      end
    end
  end

  test "easy is + and − up to 20; hard has two steps" do
    100.times do
      easy = Problems.generate("easy", "type")
      assert_match(/\A\d+ [+−] \d+\z/, easy["text"])
      assert_operator easy["answer"], :<=, 20
      assert_match(/\A\d+ [×÷] \d+ [+−] \d+\z/, Problems.generate("hard", "type")["text"])
    end
  end

  test "choice mode gives four different numbers, the answer among them" do
    100.times do
      p = Problems.generate("medium", "choice")
      assert_equal 4, p["choices"].uniq.size
      assert_includes p["choices"], p["answer"]
      assert(p["choices"].all? { _1 >= 0 })
    end
    assert_equal 4, Problems.choices(0).uniq.size
  end

  test "a new problem is never the one just answered" do
    50.times do
      first = Problems.generate("easy", "type")
      assert_not_equal first["text"], Problems.generate("easy", "type", previous: first["text"])["text"]
    end
  end

  # ── Teams ────────────────────────────────────────────────────────────────

  test "the host moves players between teams and shuffles them, only before the start" do
    ana = @players.first
    was = team_of(ana)
    assert svc.move_player!(pid(ana))
    assert_not_equal was, team_of(ana)
    assert svc.move_player!(pid(ana), was)
    assert_equal was, team_of(ana)

    assert svc.shuffle_teams!
    assert_equal({ "red" => 2, "blue" => 2 }, state["teams"].values.tally)

    pull!
    assert_not svc.move_player!(pid(ana))
    assert_not svc.shuffle_teams!
  end

  test "pulling can't start with an empty team" do
    set_teams!(@players, [])
    assert_not svc.request_start!
    assert_not svc.start_requested?

    set_teams!(@players.first(3), @players.last(1))
    assert svc.request_start!
    assert svc.start_requested?
  end

  test "a player who joins late goes to the smaller team and gets a problem" do
    set_teams!(@players.first(3), @players.last(1))
    pull!
    eva = @room.players.create!(nickname: "Eva")

    assert_equal "blue", svc.join!(pid(eva))
    assert_equal "blue", svc.join!(pid(eva))
    assert problem(eva)
    assert_equal 0, state["pulls"][pid(eva)]
  ensure
    eva&.delete
  end

  test "a team left empty gets a player from the other team" do
    set_teams!(@players.first(3), @players.last(1))
    dani = @players.last
    PlayerRemover.new(dani).remove!

    assert_equal [ 2, 1 ], state["teams"].values.tally.values_at("red", "blue")
  end

  # ── Pulling ──────────────────────────────────────────────────────────────

  test "a round puts the rope in the middle and a problem on every phone, but not its answer" do
    pull!
    s = state
    assert_equal [ "pulling", 1, 0 ], s.values_at("phase", "round", "position")
    assert_equal @players.size, s["problems"].size

    ana = @players.first
    shown = svc.player_state(pid(ana))
    assert_equal problem(ana)["text"], shown["problem"]["text"]
    assert_equal 4, shown["problem"]["choices"].size
    assert_not shown["problem"].key?("answer")
    assert_equal team_of(ana), shown["team"]
    assert_not svc.public_state.key?("problems")
  end

  test "a correct answer pulls the rope towards the team and brings a new problem" do
    ana, beto, caro, dani = @players
    set_teams!([ ana, beto ], [ caro, dani ])
    pull!
    old = problem(ana)

    result = right!(ana)
    assert_equal [ "correct", "red", -10.0, -10.0, 1, false ], result.values_at("result", "team", "step", "position", "pulls", "won")
    assert_not_equal old["id"], result["problem"]["id"]
    assert_not result["problem"].key?("answer")
    assert_equal({ "team" => "red", "count" => 1 }, result["streak"])

    assert_equal 2, right!(beto)["streak"]["count"]
    assert_equal({ "team" => "blue", "count" => 1 }, right!(caro)["streak"])
    assert_equal({ "red" => 2, "blue" => 1 }, state["team_pulls"])
    assert_in_delta(-10.0, state["position"])
  end

  test "the same problem only counts once" do
    pull!
    ana = @players.first
    old = problem(ana)
    assert_equal "correct", right!(ana)["result"]

    again = svc.answer!(pid(ana), old["id"], old["answer"])
    assert_equal "stale", again["result"]
    assert_equal problem(ana)["id"], again["problem"]["id"]
    assert_equal 1, state["pulls"][pid(ana)]
  end

  test "a wrong answer freezes the phone for 2 seconds and doesn't move the rope" do
    pull!
    ana = @players.first
    answer = problem(ana)["answer"]

    result = wrong!(ana)
    assert_equal [ "wrong", answer, 2 ], result.values_at("result", "answer", "seconds")
    assert_equal "frozen", right!(ana)["result"]
    assert_equal 0, state["position"]
    assert_equal 1, state["wrong"][pid(ana)]
    assert_operator svc.player_state(pid(ana))["frozen_seconds"], :>, 1

    @room.atomic_set("game_state.frozen.#{pid(ana)}" => Time.now.to_f - 1)
    assert_equal "correct", right!(ana)["result"]
  end

  test "a smaller team pulls harder" do
    ana, beto, caro, dani = @players
    set_teams!([ ana, beto, caro ], [ dani ])
    pull!

    assert_in_delta(-6.667, right!(ana)["step"])
    assert_in_delta 20.0, right!(dani)["step"]
  end

  test "answers only count while pulling" do
    svc.start_round!(1, 3)
    ana = @players.first
    assert_equal "closed", right!(ana)["result"]
  end

  test "the pull that reaches the end wins the round, once" do
    ana, beto, caro, dani = @players
    set_teams!([ ana, beto ], [ caro, dani ])
    pull!

    4.times { right!(caro) }
    assert_not svc.round_won?
    assert_equal [ "correct", 50.0, false ], right!(dani).values_at("result", "position", "won")
    4.times { right!(caro) }
    assert_equal true, right!(dani)["won"]
    assert_equal "blue", state["winner"]
    assert svc.round_won?
    assert_equal "closed", right!(ana)["result"]
  end

  test "when time runs out the rope's side wins; dead centre is a draw" do
    ana, beto, caro, dani = @players
    set_teams!([ ana, beto ], [ caro, dani ])
    pull!
    right!(ana)
    svc.time_up!
    assert_equal "red", state["winner"]

    pull!(2)
    svc.time_up!
    assert_equal "draw", state["winner"]
  end

  # ── Rounds and the end ───────────────────────────────────────────────────

  test "best of three ends when a team has two wins; the whole team wins" do
    ana, beto, caro, dani = @players
    set_teams!([ ana, beto ], [ caro, dani ])

    pull!(1)
    right!(ana)
    svc.time_up!
    svc.end_round!(5)
    assert_equal({ "red" => 1, "blue" => 0 }, state["wins"])
    assert_not svc.last_round?

    pull!(2)
    svc.time_up!
    svc.end_round!(5)
    assert_equal({ "red" => 1, "blue" => 0 }, state["wins"])
    assert_not svc.last_round?

    pull!(3)
    right!(beto)
    svc.time_up!
    svc.end_round!(5)
    assert svc.last_round?

    assert_equal [ pid(ana), pid(beto) ].sort, svc.finish_game!.sort
    s = @room.reload
    assert_equal [ "finished", "game_over", "red" ], [ s.status, s.game_state["phase"], s.game_state["champion"] ]
    assert_equal [ pid(ana), pid(beto) ].sort, svc.public_state["mvp"].sort
  end

  test "a drawn game has no winners" do
    pull!
    svc.time_up!
    svc.end_round!(5)
    @room.atomic_set("game_state.round" => 3)
    assert svc.last_round?
    assert_empty svc.finish_game!
    assert_equal "draw", state["champion"]
  end

  test "the host can skip the round-over screen" do
    pull!
    assert_not svc.skip!
    svc.time_up!
    svc.end_round!(5)
    assert svc.skip!
    assert svc.skipped?
  end

  test "play again starts over on the teams screen" do
    pull!
    right!(@players.first)
    Tug.new(@room.reload).setup_game!
    s = state
    assert_equal [ "teams", 0, 0 ], s.values_at("phase", "round", "position")
    assert_equal({}, s["problems"])
    assert(s["pulls"].values.all?(&:zero?))
  end
end
