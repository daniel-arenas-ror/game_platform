require "test_helper"

class GameChannelTest < ActionCable::Channel::TestCase
  setup do
    @game   = Game.create!(name: "Mind Match", code: "mind_match", description: "x")
    @room   = Room.create!(game: @game)
    @player = @room.players.create!(nickname: "Ana")
  end

  teardown do
    Player.where(room_id: @room.id).delete_all
    [ @room, @game ].each(&:delete)
  end

  test "counts a player's open subscriptions" do
    subscribe room_code: @room.code, player_id: @player.id.to_s
    assert subscription.confirmed?
    assert_equal [ 1, true ], @player.reload.attributes.values_at("connections", "connected")

    assert_equal [ @player.id ], scheduled_removals { unsubscribe }
    assert_equal [ 0, false ], @player.reload.attributes.values_at("connections", "connected")
  end

  test "a reload whose new subscription arrives first keeps the player connected" do
    @player.update!(connections: 1, connected: true)            # new page already subscribed
    subscribe room_code: @room.code, player_id: @player.id.to_s # +1 → 2
    assert_empty scheduled_removals { unsubscribe }

    assert_equal [ 1, true ], @player.reload.attributes.values_at("connections", "connected")
  end

  test "rejects a player id that was removed" do
    id = @player.id.to_s
    @player.destroy

    subscribe room_code: @room.code, player_id: id
    assert subscription.rejected?
  end

  test "the host subscribes without a player" do
    subscribe room_code: @room.code
    assert subscription.confirmed?
  end

  private

  # Records PlayerRemover.schedule calls instead of starting the 30-second timer.
  def scheduled_removals
    calls = []
    original = PlayerRemover.method(:schedule)
    PlayerRemover.define_singleton_method(:schedule) { |id| calls << id }
    yield
    calls
  ensure
    PlayerRemover.define_singleton_method(:schedule, original)
  end
end
