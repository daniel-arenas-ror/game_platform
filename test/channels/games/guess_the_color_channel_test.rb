require "test_helper"

class Games::GuessTheColorChannelTest < ActionCable::Channel::TestCase
  setup do
    @game = Game.create!(name: "Guess the Color", code: "guess_the_color", description: "x")
    @room = Room.create!(game: @game, game_state: { "total_rounds" => 1, "pick_time" => "15" })
    @room.players.create!(nickname: "Ana")
  end

  teardown do
    Player.where(room_id: @room.id).delete_all
    [ @room, @game ].each(&:delete)
  end

  test "the settings' pick time is kept, anything else falls back to 10 seconds" do
    GameServices::GuessTheColor.new(@room).setup_game!
    assert_equal 15, @room.reload.game_state["pick_time"]

    @room.update!(game_state: { "pick_time" => "99" })
    GameServices::GuessTheColor.new(@room).setup_game!
    assert_equal 10, @room.reload.game_state["pick_time"]
  end

  test "players get the chosen time to pick" do
    GameServices::GuessTheColor.new(@room).setup_game!
    subscribe(room_code: @room.code, player_id: "")
    perform :start_game_loop

    stream = "guess_the_color_room_#{@room.code}"
    picking = nil
    Timeout.timeout(10) do
      sleep 0.1 until (picking = broadcasts(stream).map { JSON.parse(_1) }.find { _1["action"] == "start_picking" })
    end
    assert_equal 15, picking["duration"]
  ensure
    unsubscribe
  end
end
