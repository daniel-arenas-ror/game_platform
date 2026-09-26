require "test_helper"

class RoomTest < ActiveSupport::TestCase
  setup do
    @game = Game.create!(name: "Test", code: "count_birds", description: "x")
    @room = Room.create!(game: @game, game_state: { "status" => "collecting", "picks" => {} })
  end

  teardown do
    @room.delete
    @game.delete
  end

  test "atomic_set keeps writes made through other copies of the room" do
    stale_copy = Room.find(@room.id)                      # e.g. the host's game-loop thread
    Room.find(@room.id).atomic_set("game_state.picks.p1" => 3) # a player's channel

    stale_copy.atomic_set("game_state.status" => "revealing")

    assert_equal({ "status" => "revealing", "picks" => { "p1" => 3 } }, @room.reload.game_state)
  end

  test "atomic_set refreshes the in-memory copy" do
    Room.find(@room.id).atomic_set("game_state.picks.p2" => 5)
    @room.atomic_set("game_state.status" => "revealing")

    assert_equal "revealing", @room.game_state["status"]
    assert_equal 5, @room.game_state.dig("picks", "p2")
  end
end
