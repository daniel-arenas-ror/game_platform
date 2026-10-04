require "test_helper"

class MatchingPairsTest < ActiveSupport::TestCase
  Pairs   = GameServices::MatchingPairs
  Catalog = GameServices::MatchingPairs::Catalog

  setup do
    @game = Game.create!(name: "Matching Pairs", code: "matching_pairs", description: "Find pairs")
    @room = Room.create!(game: @game, game_state: { "grid" => "4x4", "round_time" => "60", "category" => "animals", "total_rounds" => "2" })
    @ana, @beto = %w[Ana Beto].map { |n| @room.players.create!(nickname: n) }

    @host_svc = Pairs.new(@room)
    @host_svc.setup_game!
    @deck = @host_svc.start_round!(1)
    @host_svc.begin_play!
  end

  teardown do
    Player.where(room_id: @room.id).delete_all
    @room.delete
    @game.delete
  end

  def flip(player, index)
    # Each player's channel loads its own copy of the room.
    Pairs.new(Room.find(@room.id)).flip!(player.id, index)
  end

  # Positions of one matching pair and one card that doesn't match it.
  def pair_and_other
    a = 0
    b = @deck.each_index.find { |i| i != a && @deck[i]["key"] == @deck[a]["key"] }
    c = @deck.each_index.find { |i| @deck[i]["key"] != @deck[a]["key"] }
    [ a, b, c ]
  end

  test "setup reads the config and deals a shuffled board of pairs" do
    state = @room.reload.game_state
    assert_equal [ 4, 4, 8, 60, 2 ], state.values_at("cols", "rows", "memorize_time", "round_time", "total_rounds")
    assert_equal 16, @deck.length
    assert @deck.group_by { |c| c["key"] }.values.all? { |cards| cards.length == 2 }
    assert @deck.all? { |c| c["key"].start_with?("animals:") && c["kind"] == "image" }
  end

  test "unknown config falls back to defaults" do
    @room.update!(game_state: { "grid" => "9x9", "round_time" => "7", "category" => "cars", "total_rounds" => "4" })
    Pairs.new(@room).setup_game!

    state = @room.reload.game_state
    assert_equal [ "4x5", 120, "random", 1 ], state.values_at("grid", "round_time", "category", "total_rounds")
  end

  test "every category can fill the biggest board" do
    (Catalog::CATEGORIES + [ "random" ]).each do |category|
      cards = Catalog.sample(category, 18)
      assert_equal 18, cards.map { |c| c["key"] }.uniq.length, category
    end
  end

  test "a matching pair scores and stays found" do
    a, b, = pair_and_other

    first = flip(@ana, a)
    assert_equal "open", first[:result]
    assert_equal @deck[a], first[:item]

    second = flip(@ana, b)
    assert_equal "match", second[:result]
    assert_equal 100, second[:score]
    assert_equal 1, second[:matches]

    board = Pairs.new(@room.reload).player_board(@ana.id)
    assert_equal [ a, b ].sort, board["matched"].keys.sort
    assert_nil board["open"]
    assert_not flip(@ana, a)[:ok], "a found card can't be flipped again"
  end

  test "a wrong pair costs points but never below zero" do
    a, b, c = pair_and_other

    flip(@ana, a)
    miss = flip(@ana, c)
    assert_equal "miss", miss[:result]
    assert_equal 0, miss[:score]
    assert_nil @room.reload.game_state.dig("boards", @ana.id.to_s, "open"), "both cards flip back"

    flip(@ana, a)
    flip(@ana, b)
    d = @deck.each_index.find { |i| ![ a, b, c ].include?(i) && @deck[i]["key"] != @deck[c]["key"] }
    flip(@ana, c)
    assert_equal 90, flip(@ana, d)[:score]
    assert_equal 2, @room.reload.game_state.dig("boards", @ana.id.to_s, "wrong")
  end

  test "boards are per player" do
    a, b, = pair_and_other
    flip(@ana, a)
    assert_equal "open", flip(@beto, b)[:result], "Beto's first flip opens his own board"
  end

  test "the same card can't be flipped twice and bad indexes are rejected" do
    flip(@ana, 0)
    assert_not flip(@ana, 0)[:ok]
    assert_not flip(@ana, 16)[:ok]
    assert_not flip(@ana, "x")[:ok]
  end

  test "flips only count while the round is being played" do
    @host_svc.end_round!
    assert_not flip(@ana, 0)[:ok]
  end

  test "the round is cleared once every player found all pairs" do
    assert_not @host_svc.all_cleared?

    @deck.each_index.group_by { |i| @deck[i]["key"] }.each_value do |(i, j)|
      [ @ana, @beto ].each { |p| flip(p, i) && flip(p, j) }
    end

    assert @host_svc.all_cleared?
    assert_equal 800, @room.reload.game_state.dig("scores", @ana.id.to_s)
  end

  test "scores carry over into the next round, boards reset" do
    a, b, = pair_and_other
    flip(@ana, a)
    flip(@ana, b)

    @host_svc.start_round!(2)
    state = @room.reload.game_state
    assert_equal 100, state.dig("scores", @ana.id.to_s)
    assert_equal 0, state.dig("boards", @ana.id.to_s, "matches")
    assert_equal "memorize", state["status"]
  end

  test "players only see the layout once the round is over" do
    @room.atomic_set("game_state.status" => "memorize")
    assert_not Pairs.new(@room).public_state.key?("deck")
    assert_equal @deck, Pairs.new(@room).host_state["deck"]

    @room.atomic_set("game_state.status" => "playing")
    assert_not Pairs.new(@room).host_state.key?("deck")

    @host_svc.end_round!
    assert_equal @deck, Pairs.new(@room.reload).public_state["deck"]
  end
end
