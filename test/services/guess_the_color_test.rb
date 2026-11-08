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

  test "colours get the name that looks closest" do
    assert_equal "orange", Color.color_name(rgb(230, 120, 40))
    assert_equal "navy", Color.color_name(rgb(20, 30, 90))
    assert_equal "yellow", Color.color_name(rgb(255, 255, 0))
    assert_nil Color.color_name(nil)
  end

  test "a round: points, % match, names, and a streak bonus from the 3rd close round in a row" do
    game = Game.create!(name: "Guess the Color", code: "guess_the_color", description: "x")
    room = Room.create!(game: game)
    ana, beto = %w[Ana Beto].map { room.players.create!(nickname: _1) }
    svc = Color.new(room)
    svc.setup_game!
    orange = rgb(230, 120, 40)
    round = lambda do |ana_pick|
      room.atomic_set("game_state.current_color" => orange, "game_state.picks" => { ana.id.to_s => ana_pick })
      svc.score_round!
    end

    first = round.(orange)
    assert_equal 1000, first[:round_scores][ana.id.to_s]
    assert_equal 0, first[:round_scores][beto.id.to_s], "no pick, no points"
    assert_equal "orange", first[:target_name]
    assert_equal "orange", first[:pick_names][ana.id.to_s]
    assert_equal 100, first[:matches][ana.id.to_s]
    assert_not first[:matches].key?(beto.id.to_s)

    round.(orange)
    third = round.(orange)
    assert_equal Color::STREAK_BONUS, third[:bonuses][ana.id.to_s]
    assert_equal 1000 + Color::STREAK_BONUS, third[:round_scores][ana.id.to_s]
    assert_equal 3 * 1000 + Color::STREAK_BONUS, third[:scores][ana.id.to_s]

    missed = round.(rgb(40, 80, 220))
    assert_equal 0, missed[:streaks][ana.id.to_s], "a far pick breaks the streak"
    assert_empty missed[:bonuses]
  ensure
    Player.where(room_id: room&.id).delete_all
    Event.where(room_id: room&.id).delete_all
    room&.delete
    game&.delete
  end

  def with_room(state = {})
    game = Game.create!(name: "Guess the Color", code: "guess_the_color", description: "x")
    room = Room.create!(game: game, game_state: state)
    yield room
  ensure
    Player.where(room_id: room&.id).delete_all
    Event.where(room_id: room&.id).delete_all
    room&.delete
    game&.delete
  end

  test "every real-world thing has a colour and both languages" do
    Color::REAL_WORLD.each do |key, item|
      assert_equal 3, item["rgb"].size, key
      assert(item["rgb"].all? { _1.between?(0, 255) }, key)
      assert item["en"].present? && item["es"].present?, key
    end
  end

  test "real-world mode names a thing in the room's language, without repeating, and its colour is the target" do
    with_room("mode" => "real_world") do |room|
      room.update!(locale: "es")
      svc = Color.new(room)
      svc.setup_game!
      prompts = Array.new(5) { svc.next_target! }
      assert_equal 5, prompts.map { _1[:prompt] }.uniq.size
      first = Color::REAL_WORLD[room.reload.game_state["used_prompts"].first]
      assert_equal first["es"], prompts.first[:prompt]
      assert_equal %w[r g b].zip(first["rgb"]).to_h, prompts.first[:color]
    end
  end

  test "other modes show a colour, each for its own time" do
    with_room("mode" => "blink") do |room|
      svc = Color.new(room)
      svc.setup_game!
      assert_nil svc.next_target![:prompt]
      assert_equal 1, svc.show_time
    end
    with_room("mode" => "nonsense") do |room|
      Color.new(room).setup_game!
      assert_equal "memory", room.reload.game_state["mode"]
    end
  end

  test "awards: best average, closest pick, and the furthest pick when it was really far" do
    with_room do |room|
      room.update!(game_state: { "history" => { "a" => [ 90, 80, nil ], "b" => [ 99, 20, 30 ], "c" => [ nil, nil, nil ] } })
      awards = Color.new(room).awards.index_by { _1["key"] }
      assert_equal [ "a", 57 ], awards["eagle_eye"].values_at("player_id", "value")
      assert_equal [ "b", 99 ], awards["bullseye"].values_at("player_id", "value")
      assert_equal [ "b", 20 ], awards["creative"].values_at("player_id", "value")
    end
  end
end
