require "test_helper"

# The results page reads game_state["sorted_players"] as soon as the room is finished.
class FishermanResultsTest < ActionDispatch::IntegrationTest
  setup do
    @game = Game.create!(name: "The Fisherman", code: "fisherman", description: "Guess who knows")
    @room = Room.create!(game: @game, status: "playing", game_state: { "current_round" => 1 })
    @winner = Player.create!(room: @room, nickname: "Ana")
    @other = Player.create!(room: @room, nickname: "Bea")
    @room.atomic_set("game_state.points" => { @winner.id.to_s => 3, @other.id.to_s => 1 })
  end

  teardown do
    Player.where(room_id: @room.id).delete_all
    @room.delete
    @game.delete
  end

  test "the leaderboard is saved before the room is marked finished" do
    list_when_finished = :not_finished
    room = @room
    original = room.method(:update!)
    room.define_singleton_method(:update!) do |attrs|
      list_when_finished = Room.find(id).game_state["sorted_players"] if attrs[:status] == "finished"
      original.call(attrs)
    end

    GameServices::Fisherman.new(room).send(:update_round!)

    assert_equal "finished", room.reload.status
    assert_equal %w[Ana Bea], list_when_finished.map { |player| player["nickname"] }
  end

  test "a finished room without a leaderboard still opens" do
    @room.update!(status: "finished")

    get playing_room_path(@room.code)

    assert_response :success
  end
end
