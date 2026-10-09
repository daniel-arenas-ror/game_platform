require "test_helper"

class Games::MillionaireChannelTest < ActionCable::Channel::TestCase
  setup do
    @question = HowWantBeBillionare::Question.create!(text: "Q #{SecureRandom.hex(3)}?", points: 100, topic: "T",
                                                      answers: [ { text: "A", correct: true }, { text: "B", correct: false } ])
    @game = Game.create!(name: "Billionaire", code: "how_want_be_billionare", description: "x")
    @room = Room.create!(game: @game, game_state: { "total_rounds" => 1, "time_per_round" => 1, "advance" => "manual" })
    @room.players.create!(nickname: "Ana")
    GameServices::HowWantBeBillionare.new(@room).setup_game!
  end

  teardown do
    Player.where(room_id: @room.id).delete_all
    [ @room, @game, @question ].each(&:delete)
  end

  def stream = "millionaire_room_#{@room.code}"
  def actions = broadcasts(stream).map { |b| JSON.parse(b) }

  test "in manual mode the game waits for the host's Next" do
    subscribe(room_code: @room.code, player_id: "")
    perform :start_game_loop

    Timeout.timeout(5) { sleep 0.05 until actions.any? { |a| a["action"] == "reveal_answer" } }
    reveal = actions.find { |a| a["action"] == "reveal_answer" }
    assert_equal "manual", reveal["advance"]
    assert reveal["last"]

    sleep 1.5
    assert_not(actions.any? { |a| a["action"] == "show_leaderboard" }, "must not move on by itself")

    perform :next_question
    Timeout.timeout(5) { sleep 0.05 until actions.any? { |a| a["action"] == "show_leaderboard" } }
  end

  test "in auto mode the reveal says when the next question comes" do
    @room.atomic_set("game_state.advance" => "auto")
    subscribe(room_code: @room.code, player_id: "")
    perform :start_game_loop

    Timeout.timeout(5) { sleep 0.05 until actions.any? { |a| a["action"] == "reveal_answer" } }
    reveal = actions.find { |a| a["action"] == "reveal_answer" }
    assert_equal [ "auto", 5 ], reveal.values_at("advance", "next_in")
    unsubscribe # ends the loop instead of waiting the 5 seconds
  end

  test "players can't skip the question" do
    subscribe(room_code: @room.code, player_id: @room.players.first.id.to_s)
    assert_nothing_raised { perform :next_question }
  end
end
