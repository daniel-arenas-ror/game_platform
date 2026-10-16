require "test_helper"

class MonsterMashTest < ActiveSupport::TestCase
  Mash = GameServices::MonsterMash

  setup do
    @game = Game.create!(name: "Monster Mash", code: "monster_mash", description: "Draw")
    @room = Room.create!(game: @game, game_state: { "draw_time" => "45" })
    @players = %w[Ana Beto Caro Dani].map { |n| @room.players.create!(nickname: n) }
    Mash.new(@room).setup_game!
  end

  teardown do
    # Only this test's records: tests run in parallel against one database.
    MonsterMash::Drawing.where(room_id: @room.id).delete_all
    Player.where(room_id: @room.id).delete_all
    Event.where(room_id: @room.id).delete_all
    @room.delete
    @game.delete
  end

  # Each player's channel loads its own copy of the room.
  def svc = Mash.new(Room.find(@room.id))
  def state = @room.reload.game_state
  def order = state["order"]
  def player(pid) = @players.find { |p| p.id.to_s == pid }

  def stroke(id, points = [ [ 0.5, 0.5 ], [ 0.6, 0.6 ] ])
    { "id" => id, "color" => "#111827", "size" => 10, "points" => points }
  end

  # Plays every drawing round: each player draws one stroke and taps Done.
  def draw_all_rounds
    3.times do |round|
      svc.start_round!(round, 60)
      order.each_with_index { |pid, i| svc.save_stroke!(pid, stroke(i + 1)); svc.done!(pid) }
    end
  end

  # ── Setup ────────────────────────────────────────────────────────────────

  test "setup reads the settings, picks a theme and names one monster per player" do
    s = state
    assert_equal [ "waiting", -1, 45 ], s.values_at("phase", "round", "draw_time")
    assert_includes Mash::WORDS["en"]["themes"], s["theme"]
    assert_equal 4, s["monsters"].size
    assert_equal 4, s["monsters"].map { _1["name"] }.uniq.size
    assert_equal s["order"], s["monsters"].map { _1["starter"] }
    assert_equal({ 0 => 4 }, s["scores"].values.tally)
  end

  test "a Spanish room gets a Spanish theme and names; a bad time falls back to 60 seconds" do
    @room.update!(locale: "es", game_state: { "draw_time" => "7" })
    Mash.new(@room).setup_game!

    assert_includes Mash::WORDS["es"]["themes"], state["theme"]
    assert_equal 60, state["draw_time"]
    assert(state["monsters"].all? { |m| Mash::WORDS["es"]["names"]["titles"].include?(m["name"].split.first) })
  end

  test "each round everyone draws one part, and every monster gets three different artists" do
    (3..8).each do |count|
      artists = Array.new(count) { [] }
      count.times do |position|
        3.times { |round| artists[Mash.monster_for(position, round, count)] << position }
      end
      assert(artists.all? { |a| a.uniq.size == 3 }, "#{count} players")
    end
  end

  test "a round gives each player a drawing on their monster" do
    svc.start_round!(0, 60)
    s = state
    assert_equal [ "drawing", 0 ], s.values_at("phase", "round")
    assert_equal 4, MonsterMash::Drawing.where(room_id: @room.id, part: "head").count
    assert_equal order, s["monsters"].map { _1["artists"]["head"] } # everyone starts their own

    svc.start_round!(1, 60)
    bodies = state["monsters"].map { _1["artists"]["body"] }
    assert_equal order.sort, bodies.sort
    assert(state["monsters"].none? { |m| m["artists"]["head"] == m["artists"]["body"] })
  end

  # ── Drawing ──────────────────────────────────────────────────────────────

  test "heads have no guide; a body gets the bottom strip of its head" do
    svc.start_round!(0, 60)
    head_artist = order[0]
    assert_nil svc.assignment(head_artist)["guide"]
    svc.save_stroke!(head_artist, stroke(1, [ [ 0.5, 0.2 ], [ 0.5, 0.9 ] ])) # a neck going down
    svc.save_stroke!(head_artist, stroke(2, [ [ 0.1, 0.1 ], [ 0.2, 0.2 ] ])) # an eye, too high to show

    svc.start_round!(1, 60)
    body_artist = state["monsters"][0]["artists"]["body"]
    task = Mash.new(@room.reload).assignment(body_artist)
    assert_equal [ 0, "body" ], task.values_at("monster", "part")
    assert_equal 1, task["guide"].size
    assert_equal [ [ 0.5, 0.0 ], [ 0.5, 0.3333 ] ], task["guide"].first["points"]
  end

  test "a line that leaves the strip and comes back is cut in two" do
    guide = Mash.guide_strip([ stroke(1, [ [ 0.1, 0.95 ], [ 0.2, 0.5 ], [ 0.3, 0.95 ] ]) ])
    assert_equal 2, guide.size
    assert_equal [ [ 0.1, 0.6667 ], [ 0.2, 0.0 ] ], guide[0]["points"]
    assert_equal [ [ 0.2, 0.0 ], [ 0.3, 0.6667 ] ], guide[1]["points"]
  end

  test "strokes are saved once; undo and clear work whatever order they arrive in" do
    svc.start_round!(0, 60)
    pid = order.first

    assert svc.save_stroke!(pid, stroke(1))
    assert_not svc.save_stroke!(pid, stroke(1)) # the same stroke twice
    assert svc.undo!(pid, 2)                     # undo arrives before its stroke
    assert_not svc.save_stroke!(pid, stroke(2))
    svc.save_stroke!(pid, stroke(3))
    svc.clear!(pid, 3)
    assert_not svc.save_stroke!(pid, stroke(3))

    assert_empty svc.assignment(pid)["strokes"]
    svc.save_stroke!(pid, stroke(4))
    assert_equal [ 4 ], svc.assignment(pid)["strokes"].map { _1["id"] }
  end

  test "Done locks the drawing; the round is over when everyone still in the room is done" do
    svc.start_round!(0, 60)
    a, b, c, d = order
    [ a, b, c ].each { svc.done!(_1) }
    assert_not svc.save_stroke!(a, stroke(1))
    assert_not svc.all_done?
    assert_equal [ a, b, c ].sort, svc.done_ids.sort

    @room.update!(status: "playing")
    PlayerRemover.new(player(d)).remove!
    assert svc.all_done?
  end

  test "nothing can be drawn outside a drawing round" do
    pid = order.first
    assert_not svc.save_stroke!(pid, stroke(1))
    assert_not svc.done!(pid)
    assert_nil svc.assignment(pid)
  end

  # ── Reveal, vote, scores ─────────────────────────────────────────────────

  test "the reveal shows one monster at a time with its three drawings" do
    draw_all_rounds
    svc.start_reveal!
    monster = svc.reveal!(0)

    assert_equal %w[head body legs], monster["parts"].keys
    assert(monster["parts"].values.all? { _1.size == 1 })
    shown = Mash.new(@room.reload).public_state
    assert_equal 1, shown["monsters"].size
    assert_equal 4, shown["monsters_count"]
  end

  test "players vote once, never for the monster they started" do
    draw_all_rounds
    svc.start_vote!(30)
    a = order.first

    assert_not svc.vote!(a, 0) # Ana started monster 0
    assert_not svc.vote!(a, 9)
    assert svc.vote!(a, 1)
    assert_not svc.vote!(a, 2)
    assert_not svc.all_voted?
    assert_equal [ a ], svc.voted_ids
  end

  test "each vote is a point for every artist of the monster" do
    draw_all_rounds
    svc.start_vote!(30)
    a, b, c, d = order
    svc.vote!(a, 1)
    svc.vote!(b, 2)
    svc.vote!(c, 1)
    svc.vote!(d, 1)

    result = svc.end_vote!
    assert_equal [ 1 ], result["top"]
    assert_equal({ "1" => 3, "2" => 1 }, result["tally"])
    artists1 = state["monsters"][1]["artists"].values
    artists2 = state["monsters"][2]["artists"].values
    order.each do |pid|
      expected = (artists1.include?(pid) ? 3 : 0) + (artists2.include?(pid) ? 1 : 0)
      assert_equal expected, state["scores"][pid], player(pid).nickname
    end
    assert_equal state["scores"].values.max, state["scores"][result["winners"].first]
    assert_equal "results", state["phase"]
  end

  test "no votes: no Monster of the Night and no winner" do
    draw_all_rounds
    svc.start_vote!(30)
    result = svc.end_vote!
    assert_empty result["top"]
    assert_empty result["winners"]
  end

  # ── Privacy and the end ──────────────────────────────────────────────────

  test "screens get no drawings, names or votes before their time; a phone gets its own task" do
    svc.start_round!(0, 60)
    house = Mash.new(@room.reload)
    shown = house.public_state
    assert_empty shown["monsters"]
    assert_empty shown.keys & %w[votes order loop_id done]

    mine = house.player_state(order.first)
    assert_equal "head", mine["assignment"]["part"]
    assert_equal 0, mine["my_monster"]
  end

  test "the gallery has every monster, and Play Again starts over with fresh drawings" do
    draw_all_rounds
    assert_equal 4, svc.gallery.size
    old_game = state["game_id"]

    Mash.new(@room.reload).setup_game!
    assert_not_equal old_game, state["game_id"]
    assert_equal 0, MonsterMash::Drawing.where(room_id: @room.id).count
  end

  test "both languages have 30 themes and every name list filled" do
    %w[en es].each do |locale|
      words = Mash::WORDS[locale]
      assert_equal 30, words["themes"].uniq.size, locale
      %w[titles first second places].each { |key| assert_operator words["names"][key].size, :>=, 10, "#{locale} #{key}" }
    end
  end
end
