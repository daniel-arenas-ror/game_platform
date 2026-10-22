require "test_helper"

# Room#broadcast_analytics: the Google Analytics funnel events the host's screen sends.
class RoomAnalyticsTest < ActiveSupport::TestCase
  include ActionCable::TestHelper

  setup do
    @game = Game.create!(name: "Mind Match", code: "mind_match", description: "x", slug: "mind-match-#{SecureRandom.hex(3)}")
    @room = Room.create!(game: @game, status: "lobby")
    @room.players.create!(nickname: "Ana")
    @stream = RoomChannel.stream_for_room(@room.code)
  end

  teardown do
    # Only this test's records: tests run in parallel against one database.
    Player.where(room_id: @room.id).delete_all
    Room.where(id: @room.id).delete_all
    Game.where(id: @game.id).delete_all
  end

  def event_for(&)
    assert_broadcasts(@stream, 1, &)
    broadcasts(@stream).last.then { |m| ActiveSupport::JSON.decode(m) }
  end

  test "the first game from the lobby is game_started, with the game and the players" do
    message = event_for { @room.update!(status: "playing") }
    assert_equal "analytics", message["action"]
    assert_equal "game_started", message["event"]
    assert_equal({ "game_name" => @game.slug, "player_count" => 1 }, message["params"])
  end

  test "game over is game_finished, and starting again is play_again" do
    @room.update!(status: "playing")
    assert_equal "game_finished", event_for { @room.update!(status: "finished") }["event"]
    assert_equal "play_again", event_for { @room.update!(status: "playing") }["event"]
  end

  test "nothing is sent when the status stays the same or goes back to the lobby" do
    @room.update!(status: "finished")
    clear_messages(@stream)
    assert_no_broadcasts(@stream) do
      @room.update!(game_state: { "x" => 1 })
      @room.update!(status: "lobby")
    end
  end
end
