require "test_helper"

class CharacterHuntTest < ActiveSupport::TestCase
  Hunt  = GameServices::CharacterHunt
  Crowd = GameServices::CharacterHunt::Crowd

  setup do
    @game = Game.create!(name: "Character Hunt", code: "character_hunt", description: "Find them")
    @room = Room.create!(game: @game, game_state: { "total_rounds" => "3", "round_time" => "60", "difficulty" => "hard" })
    @players = %w[Ana Beto Caro Dani].map { |n| @room.players.create!(nickname: n) }
    Hunt.new(@room).setup_game!
  end

  teardown do
    # Only this test's records: tests run in parallel against one database.
    Player.where(room_id: @room.id).delete_all
    Event.where(room_id: @room.id).delete_all
    @room.delete
    @game.delete
  end

  # Each player's channel loads its own copy of the room.
  def svc = Hunt.new(Room.find(@room.id))
  def state = @room.reload.game_state
  def pid(player) = player.id.to_s

  # The middle of a character's box, where a finger would tap it.
  def spot(index)
    c = state["scene"]["characters"][index]
    [ c["x"], c["y"] - c["h"] / 2 ]
  end

  # A character whose middle no one else covers, so a tap there lands on it.
  def clear_character(except:)
    s = state["scene"]
    (0...s["characters"].size).find { |i| i != except && Crowd.hit(s, *spot(i)) == i }
  end

  def search!(round = 1)
    svc.start_round!(round, 5)
    svc.start_search!
  end

  def find!(player) = svc.tap!(pid(player), *spot(state["target_index"]))

  # ── Setup ────────────────────────────────────────────────────────────────

  test "setup reads the settings and plans a scene per round" do
    s = state
    assert_equal [ "waiting", 0, 3, 60, "hard" ], s.values_at("phase", "round", "total_rounds", "round_time", "difficulty")
    assert_equal 3, s["scene_order"].uniq.size
    assert_equal({ 0 => 4 }, s["scores"].values.tally)
  end

  test "bad settings fall back to the defaults" do
    @room.update!(game_state: { "total_rounds" => "99", "round_time" => "7", "difficulty" => "insane" })
    Hunt.new(@room).setup_game!
    assert_equal [ 5, 90, "normal" ], state.values_at("total_rounds", "round_time", "difficulty")
  end

  test "scenes never repeat twice in a row and all are used before any repeats" do
    order = Hunt.scene_order(8)
    assert_equal 8, order.size
    assert(order.each_cons(2).none? { |a, b| a == b })
    assert_equal Crowd::SCENES.keys.sort, order.first(Crowd::SCENES.size).sort
  end

  # ── The crowd ────────────────────────────────────────────────────────────

  test "a crowd has one target, its decoys and fillers that don't look like it" do
    Crowd::SCENES.each_key do |scene_id|
      crowd  = Crowd.build(scene_id, count: 150, decoys: 4, size: 0.85)
      people = crowd["scene"]["characters"]
      target = people[crowd["target_index"]]["traits"]
      close  = people.map { |c| Crowd.distance(c["traits"], target) }

      assert_operator people.size, :>=, 140, scene_id
      assert_equal 1, close.count(0), "only one target in the #{scene_id}"
      assert_equal 4, close.count { |d| d.between?(1, 2) }, "4 decoys in the #{scene_id}"
      assert(close.all? { |d| d.zero? || d <= 2 || d >= Crowd::FILLER_DISTANCE })
    end
  end

  test "people stand where the scene allows, smaller further back, back to front" do
    scene  = Crowd::SCENES["park"]
    crowd  = Crowd.build("park", count: 100, decoys: 2)
    people = crowd["scene"]["characters"]

    assert_equal people.map { _1["y"] }.sort, people.map { _1["y"] }
    people.each do |c|
      assert(scene["areas"].any? { |x0, y0, x1, y1| c["x"].between?(x0, x1) && c["y"].between?(y0, y1) })
      assert(scene["holes"].none? { |x0, y0, x1, y1| c["x"].between?(x0, x1) && c["y"].between?(y0, y1) })
    end
    back, front = people.first, people.last
    assert_operator back["h"], :<, front["h"]
  end

  test "nobody covers much of the target" do
    5.times do
      crowd  = Crowd.build("plaza", count: 150, decoys: 4, size: 0.85)
      s      = crowd["scene"]
      t      = crowd["target_index"]
      box    = Crowd.box(s["characters"][t], s["ratio"])
      hidden = s["characters"][(t + 1)..].sum { |c| Crowd.overlap(box, Crowd.box(c, s["ratio"])) }
      assert_operator hidden, :<=, Crowd.area(box) * 0.5
    end
  end

  test "traits a character can't show are dropped" do
    traits = Crowd.normalize({ "hair" => 0, "beard" => 0, "hair_color" => 2, "pattern" => 0, "pattern_color" => 1,
                               "hat" => 0, "hat_color" => 3, "extra" => 0, "extra_color" => 4 })
    assert_equal({ "hair" => 0, "beard" => 0, "pattern" => 0, "hat" => 0, "extra" => 0 }, traits)
  end

  test "a tap lands on the character in front" do
    scene = { "ratio" => 1.0, "characters" => [
      { "x" => 0.5, "y" => 0.5, "h" => 0.2 }, { "x" => 0.52, "y" => 0.55, "h" => 0.2 }
    ] }
    assert_equal 1, Crowd.hit(scene, 0.51, 0.45)
    assert_equal 0, Crowd.hit(scene, 0.46, 0.3)
    assert_nil Crowd.hit(scene, 0.9, 0.9)
  end

  # ── Rounds ───────────────────────────────────────────────────────────────

  test "a round shows who to find but not where they are" do
    svc.start_round!(1, 5)
    s = state
    assert_equal [ "intro", 1 ], s.values_at("phase", "round")
    assert_equal s["scene_order"][0], s["scene"]["id"]
    assert_equal s["scene"]["characters"][s["target_index"]]["traits"], s["target"]

    shown = svc.public_state
    assert_equal s["target"], shown["target"]
    assert_not shown.key?("target_index")
    assert_not shown.key?("scene_order")
  end

  test "the first three finders score 3, 2 and 1, then the round is full" do
    search!
    ana, beto, caro, dani = @players

    assert_equal [ "found", 1, 3 ], find!(beto).values_at("result", "place", "points")
    assert_equal "already", find!(beto)["result"]
    assert_not svc.round_over?
    assert_equal [ 2, 2 ], find!(dani).values_at("place", "points")
    assert_equal [ 3, 1 ], find!(ana).values_at("place", "points")
    assert svc.round_over?
    assert_equal "closed", find!(caro)["result"]

    assert_equal({ pid(beto) => 3, pid(dani) => 2, pid(ana) => 1, pid(caro) => 0 }, state["scores"])
    assert_equal [ pid(beto), pid(dani), pid(ana) ], state["finders"].map { _1["id"] }
    assert_equal [ 3, 2, 1 ], state["finders"].map { _1["points"] }
  end

  test "a wrong tap freezes the phone; tapping nobody doesn't" do
    search!
    ana = @players.first
    other = clear_character(except: state["target_index"])

    assert_equal "miss", svc.tap!(pid(ana), 0.5, 0.01)["result"]
    result = svc.tap!(pid(ana), *spot(other))
    assert_equal [ "wrong", other ], result.values_at("result", "index")
    assert_equal "frozen", find!(ana)["result"]
    assert_equal 1, state["wrong"][pid(ana)]
    assert_equal 3, result["seconds"]
    assert_in_delta 3, svc.player_state(pid(ana))["frozen_seconds"], 0.5

    @room.atomic_set("game_state.frozen.#{pid(ana)}" => Time.now.to_f - 1)
    assert_equal "found", find!(ana)["result"]
  end

  test "taps only count while searching, from players, with real coordinates" do
    svc.start_round!(1, 5)
    ana = @players.first
    assert_equal "closed", find!(ana)["result"]

    svc.start_search!
    assert_equal "closed", svc.tap!("someone-else", *spot(state["target_index"]))["result"]
    assert_equal "closed", svc.tap!(pid(ana), "left", nil)["result"]
  end

  test "with fewer than three players left the round ends when they've all found it" do
    search!
    @players.last(2).each(&:delete)
    find!(@players[0])
    assert_not svc.round_over?
    find!(@players[1])
    assert svc.round_over?
  end

  test "a new round starts clean and the reveal shows the target" do
    search!
    find!(@players.first)
    svc.end_round!(5)
    assert_equal "reveal", state["phase"]
    assert_equal state["target_index"], svc.public_state["target_index"]

    svc.start_round!(2, 5)
    assert_equal [ [], {}, 2 ], state.values_at("finders", "frozen", "round")
    assert_equal 3, state["scores"][pid(@players.first)]
  end

  test "game over crowns the top scorers" do
    search!
    find!(@players[0])
    find!(@players[1])
    s = svc
    assert_not s.last_round?
    assert_equal [ pid(@players[0]) ], s.finish_game!
    assert_equal [ "finished", "game_over" ], [ @room.reload.status, state["phase"] ]
  end
end
