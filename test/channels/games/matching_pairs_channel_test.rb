require "test_helper"

class Games::MatchingPairsChannelTest < ActionCable::Channel::TestCase
  setup do
    @game = Game.create!(name: "Matching Pairs", code: "matching_pairs", description: "Find pairs")
    @room = Room.create!(game: @game, game_state: { "grid" => "4x4", "category" => "numbers" })
    @ana  = @room.players.create!(nickname: "Ana")

    svc = GameServices::MatchingPairs.new(@room)
    svc.setup_game!
    @deck = svc.start_round!(1)
  end

  teardown do
    Player.where(room_id: @room.id).delete_all
    @room.delete
    @game.delete
  end

  test "the host also streams the layout, players don't" do
    subscribe(room_code: @room.code, player_id: "")
    assert_has_stream "matching_pairs_room_#{@room.code}_host"
    assert_equal @deck, transmissions.last["state"]["deck"]

    unsubscribe
    subscribe(room_code: @room.code, player_id: @ana.id.to_s)
    assert_has_stream "matching_pairs_room_#{@room.code}"
    assert_has_no_stream "matching_pairs_room_#{@room.code}_host"
    assert_not transmissions.last["state"].key?("deck")
  end

  test "a flip is answered privately and a pair is announced to the room" do
    GameServices::MatchingPairs.new(@room).begin_play!
    subscribe(room_code: @room.code, player_id: @ana.id.to_s)

    a = 0
    b = @deck.each_index.find { |i| i != a && @deck[i]["key"] == @deck[a]["key"] }

    perform :flip, index: a
    assert_equal({ "action" => "flip_result", "result" => "open" }, transmissions.last.slice("action", "result"))

    assert_broadcast_on("matching_pairs_room_#{@room.code}",
                        action: "progress", player_id: @ana.id.to_s, score: 100, matches: 1, cleared: false, match: true) do
      perform :flip, index: b
    end
    assert_equal @deck[b], transmissions.last["item"]
  end
end
