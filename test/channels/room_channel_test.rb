require "test_helper"

class RoomChannelTest < ActionCable::Channel::TestCase
  setup do
    @game   = Game.create!(name: "Mind Match", code: "mind_match", description: "x")
    @room   = Room.create!(game: @game)
    @player = @room.players.create!(nickname: "Ana")
  end

  teardown do
    Player.where(room_id: @room.id).delete_all
    [ @room, @game ].each(&:delete)
  end

  test "a player listens without counting as connected" do
    subscribe room_code: @room.code, player_id: @player.id.to_s
    assert subscription.confirmed?
    assert_has_stream "room_#{@room.code}"
    assert_equal 0, @player.reload.connections
  end

  test "rejects a player who was removed" do
    id = @player.id.to_s
    @player.destroy
    subscribe room_code: @room.code, player_id: id
    assert subscription.rejected?
  end
end
