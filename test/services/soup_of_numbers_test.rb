require "test_helper"

class SoupOfNumbersTest < ActiveSupport::TestCase
  Soup = GameServices::SoupOfNumbers

  setup do
    @game = Game.create!(name: "Soup of Numbers", code: "soup_of_numbers", description: "Find numbers")
    @room = Room.create!(game: @game, game_state: { "grid_size" => "8", "max_digits" => "5", "total_rounds" => "5" })
    @ana, @beto = %w[Ana Beto].map { |n| @room.players.create!(nickname: n) }

    @host_svc = Soup.new(@room)
    @host_svc.setup_game!
    @target = @host_svc.start_round!(1)
  end

  teardown do
    Player.where(room_id: @room.id).delete_all
    @room.delete
    @game.delete
  end

  def claim(player, cells)
    # Each player's channel loads its own copy of the room.
    Soup.new(Room.find(@room.id)).claim!(player.id, cells)
  end

  test "the soup hides every target where it says" do
    state = @room.reload.game_state
    assert_equal 8, state["grid"].length
    assert state["grid"].all? { |row| row.match?(/\A\d{8}\z/) }
    assert_equal 5, state["total_rounds"]
    assert_equal state["targets"].length, state["targets"].map { |t| t["number"] }.uniq.length

    state["targets"].each do |t|
      assert t["number"].length.between?(2, 5)
      assert_equal t["number"], Soup.read(state["grid"], t["cells"])
    end
  end

  test "lines are accepted in either tap order but must be straight and gap-free" do
    assert_equal [ [ 0, 0 ], [ 0, 1 ] ], Soup.normalize_line([ [ 0, 1 ], [ 0, 0 ] ], 8)
    assert_equal [ [ 0, 3 ], [ 1, 2 ], [ 2, 1 ] ], Soup.normalize_line([ [ 2, 1 ], [ 1, 2 ], [ 0, 3 ] ], 8)
    assert_nil Soup.normalize_line([ [ 0, 0 ], [ 0, 2 ] ], 8)
    assert_nil Soup.normalize_line([ [ 0, 0 ], [ 0, 1 ], [ 1, 1 ] ], 8)
    assert_nil Soup.normalize_line([ [ 7, 7 ], [ 7, 8 ] ], 8)
  end

  test "the first correct claim wins the round and scores by length" do
    cells = @target["cells"]

    result = claim(@ana, cells.reverse)
    assert result[:ok]
    assert_equal @target["number"].length * 50, result[:points]

    assert_not claim(@beto, cells)[:ok]

    state = @room.reload.game_state
    assert_equal @ana.id.to_s, state["round_winner"]
    assert_equal "found", state["status"]
    assert_equal @target["number"].length * 50, state["scores"][@ana.id.to_s]
    assert_equal 0, state["scores"][@beto.id.to_s]
    assert_equal [ @target["number"] ], state["found"].map { |f| f["number"] }
  end

  test "wrong digits or wrong length are rejected" do
    cells = @target["cells"]
    assert_not claim(@ana, cells.first(cells.length - 1))[:ok]

    grid  = @room.game_state["grid"]
    wrong = (0..7).to_a.product((0..7).to_a).each_cons(cells.length).map(&:to_a).find do |line|
      Soup.normalize_line(line, 8) && Soup.read(grid, line) != @target["number"]
    end
    assert_not claim(@ana, wrong)[:ok]
    assert_nil @room.reload.game_state["round_winner"]
  end

  test "a missed round reveals the planted copy and blocks late claims" do
    entry = @host_svc.miss_round!
    assert_equal @target["cells"], entry["cells"]
    assert_nil entry["player_id"]
    assert_not claim(@ana, @target["cells"])[:ok]
  end

  test "players never receive the hidden target positions" do
    public_state = Soup.new(@room.reload).public_state
    assert_not public_state.key?("targets")
    assert_equal @target["number"], public_state["target"]["number"]
  end
end
