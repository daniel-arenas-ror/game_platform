require "test_helper"

class MindMatchTest < ActiveSupport::TestCase
  setup do
    @game = Game.create!(name: "Mind Match", code: "mind_match", description: "Match words")
    @room = Room.create!(game: @game)
    @ana, @beto, @caro = %w[Ana Beto Caro].map { |n| @room.players.create!(nickname: n) }

    # The host's game loop keeps its own long-lived Room object, like the channel thread does.
    @host_svc = GameServices::MindMatch.new(@room)
    @host_svc.setup_game!
    @host_svc.pick_category!
    @room.atomic_set("game_state.status" => "collecting")
  end

  teardown do
    Player.where(room_id: @room.id).delete_all
    @room.delete
    @game.delete
  end

  def submit(player, word)
    # Each player's channel loads its own copy of the room.
    GameServices::MindMatch.new(Room.find(@room.id)).add_answer(player.id, word)
  end

  test "answers survive the host moving the round to revealing" do
    assert submit(@ana, "sand")
    assert submit(@beto, "Sand")

    @room.atomic_set("game_state.status" => "revealing")
    result = @host_svc.score_round!

    assert_equal({ @ana.id.to_s => "sand", @beto.id.to_s => "Sand" }, result[:answers])
    assert_equal 2, result[:round_scores][@ana.id.to_s]
    assert_equal 2, result[:round_scores][@beto.id.to_s]
    assert_equal 0, result[:round_scores][@caro.id.to_s]
  end

  test "a player can only answer once per round" do
    assert submit(@ana, "sand")
    assert_not submit(@ana, "shell")
    assert_equal "sand", @room.reload.game_state["answers"][@ana.id.to_s]
  end

  test "answers are rejected once the round stops collecting" do
    @room.atomic_set("game_state.status" => "revealing")
    assert_not submit(@ana, "late")
    assert_empty @room.reload.game_state["answers"]
  end
end
