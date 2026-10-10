require "test_helper"

class Games::MillionaireChannelTest < ActionCable::Channel::TestCase
  setup do
    @question = HowWantBeBillionare::Question.create!(text: "Q #{SecureRandom.hex(3)}?", points: 100, topic: "T",
                                                      answers: [ { text: "A", correct: true }, { text: "B", correct: false } ])
    @game = Game.create!(name: "Billionaire", code: "how_want_be_billionare", description: "x")
    @room = Room.create!(game: @game, game_state: { "total_rounds" => 1, "time_per_round" => 1, "advance" => "manual" })
    @room.players.create!(nickname: "Ana")
    GameServices::HowWantBeBillionare.new(@room).setup_game!
    # setup_game! samples any question, maybe another parallel test's that gets deleted mid-game: use ours.
    @room.atomic_set("game_state.question_id" => @question.id, "game_state.question" => @question.text,
                     "game_state.answers" => @question.answers)
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

  test "a phone that connects after the question went out still gets it, with the time left" do
    ana = @room.players.first
    @room.update!(status: "playing")
    @room.atomic_set("game_state.screen" => { "action" => "send_question", "round" => 1, "total" => 1, "text" => @question.text,
                                              "options" => @question.answers.as_json, "duration" => 10,
                                              "ends_at" => Time.current.to_f + 7.5 })

    subscribe(room_code: @room.code, player_id: ana.id.to_s)
    question = transmissions.find { |m| m["action"] == "send_question" }
    assert_equal [ @question.text, 7, nil ], question.values_at("text", "duration", "my_choice")
  end

  test "a phone that reconnects after answering sees its answer locked" do
    ana = @room.players.first
    @room.update!(status: "playing")
    @room.atomic_set("game_state.answers_history" => { @question.id.to_s => { ana.id.to_s => 1 } },
                     "game_state.screen" => { "action" => "send_question", "ends_at" => Time.current.to_f + 5 })

    subscribe(room_code: @room.code, player_id: ana.id.to_s)
    assert_equal 1, transmissions.find { |m| m["action"] == "send_question" }["my_choice"]
  end

  test "a question whose time is up isn't sent again, but the reveal is" do
    ana = @room.players.first
    @room.update!(status: "playing")
    @room.atomic_set("game_state.screen" => { "action" => "send_question", "ends_at" => Time.current.to_f - 1 })
    subscribe(room_code: @room.code, player_id: ana.id.to_s)
    assert_empty transmissions
    unsubscribe

    @room.atomic_set("game_state.screen" => { "action" => "reveal_answer", "advance" => "manual", "ends_at" => nil })
    subscribe(room_code: @room.code, player_id: ana.id.to_s)
    assert_equal "reveal_answer", transmissions.last["action"]
  end

  test "the game loop saves each screen for late phones" do
    subscribe(room_code: @room.code, player_id: "")
    perform :start_game_loop

    Timeout.timeout(5) { sleep 0.05 until actions.any? { |a| a["action"] == "send_question" } }
    Timeout.timeout(5) { sleep 0.05 until @room.reload.game_state.dig("screen", "action") }
    assert_includes %w[send_question reveal_answer], @room.game_state["screen"]["action"]
    unsubscribe
  end
end
