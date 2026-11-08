require "test_helper"

class HowWantBeBillionareTest < ActiveSupport::TestCase
  setup do
    @questions = 3.times.map do |i|
      HowWantBeBillionare::Question.create!(text: "Q#{i}?", points: 100, topic: "T",
                                             answers: [ { text: "A", correct: true }, { text: "B", correct: false } ])
    end
    @game = Game.create!(name: "Billionaire", code: "how_want_be_billionare", description: "x")
    @room = Room.create!(game: @game, game_state: { "total_rounds" => 10, "time_per_round" => 20 })
    @ana  = @room.players.create!(nickname: "Ana")
  end

  teardown do
    Player.where(room_id: @room.id).delete_all
    [ @room, @game, *@questions ].each(&:delete)
  end

  test "play again resets points, keeps settings and skips questions already asked" do
    svc = GameServices::HowWantBeBillionare.new(@room)
    assert svc.setup_game!
    first_id = @room.reload.game_state["question_id"].to_s
    @room.atomic_set("game_state.user_points.#{@ana.id}" => 700)

    assert GameServices::HowWantBeBillionare.new(@room.reload).setup_game!(keep_asked_questions: true)

    state = @room.reload.game_state
    assert_equal 0, state["user_points"][@ana.id.to_s]
    assert_equal [ 10, 20 ], state.values_at("total_rounds", "time_per_round")
    assert_not_equal first_id, state["question_id"].to_s
    assert_includes state["asked_question_ids"], first_id
  end

  # Ana answers right on every question; question_id is fixed so other tests' questions don't matter.
  def answer_round(svc, round, seconds:, right: true)
    q = @questions.first
    @room.atomic_set("game_state.question_id" => q.id, "game_state.question_points" => 100,
                     "game_state.question_duration" => 20,
                     "game_state.answers_history.#{q.id}" => { @ana.id.to_s => right ? 0 : 1 },
                     "game_state.answer_seconds.#{q.id}"  => { @ana.id.to_s => seconds })
    svc.score_round!(round)
  end

  test "faster right answers earn more, down to half at the buzzer" do
    svc = GameServices::HowWantBeBillionare.new(@room)
    svc.setup_game!

    assert_equal 100, answer_round(svc, 0, seconds: 0)[:round_scores][@ana.id.to_s]
    @room.atomic_set("game_state.streaks" => {})
    assert_equal 80, answer_round(svc, 1, seconds: 8)[:round_scores][@ana.id.to_s]
    @room.atomic_set("game_state.streaks" => {})
    assert_equal 50, answer_round(svc, 2, seconds: 20)[:round_scores][@ana.id.to_s]
  end

  test "3 right in a row pays ×1.5, 5 in a row ×2, and a miss starts over" do
    svc = GameServices::HowWantBeBillionare.new(@room)
    svc.setup_game!

    scores = 5.times.map { |round| answer_round(svc, round, seconds: 0)[:round_scores][@ana.id.to_s] }
    assert_equal [ 100, 100, 150, 150, 200 ], scores

    result = answer_round(svc, 5, seconds: 0, right: false)
    assert_equal 0, result[:streaks][@ana.id.to_s]
    assert_nil result[:round_scores][@ana.id.to_s]
    assert_equal 100, answer_round(svc, 6, seconds: 0)[:round_scores][@ana.id.to_s]
  end

  test "the final question counts double" do
    svc = GameServices::HowWantBeBillionare.new(@room)
    svc.setup_game!
    assert svc.final_round?(9)
    assert_equal 200, answer_round(svc, 9, seconds: 0)[:round_scores][@ana.id.to_s]
  end

  test "questions climb the points ladder" do
    svc = GameServices::HowWantBeBillionare.new(@room)
    assert_equal [ 100, 200, 300, 400, 500, 600, 700, 800, 900, 1000 ],
                 10.times.map { |round| svc.send(:ladder_points, round) }
  end

  test "an answer remembers how long it took" do
    svc = GameServices::HowWantBeBillionare.new(@room)
    svc.setup_game!
    svc.start_question!(20)
    @room.atomic_set("game_state.question_started_at" => Time.current.to_f - 3)
    svc.add_answer(@ana.id, 0)

    seconds = @room.reload.game_state.dig("answer_seconds", @room.game_state["question_id"].to_s, @ana.id.to_s)
    assert_in_delta 3, seconds, 0.5
  end

  test "the round can end early once every connected player answered" do
    svc = GameServices::HowWantBeBillionare.new(@room)
    svc.setup_game!
    @ana.set(connected: true)
    assert_not svc.everyone_answered?

    svc.add_answer(@ana.id, 0)
    assert svc.everyone_answered?
  end

  test "the reveal counts the picks, keeps the old totals and names a new leader" do
    beto = @room.players.create!(nickname: "Beto")
    svc  = GameServices::HowWantBeBillionare.new(@room)
    svc.setup_game!
    @room.atomic_set("game_state.user_points" => { @ana.id.to_s => 0, beto.id.to_s => 50 })
    q = @questions.first
    @room.atomic_set("game_state.question_id" => q.id, "game_state.question_points" => 100,
                     "game_state.question_duration" => 20,
                     "game_state.answers_history.#{q.id}" => { @ana.id.to_s => 0, beto.id.to_s => 1 },
                     "game_state.answer_seconds.#{q.id}"  => { @ana.id.to_s => 0 })

    result = svc.score_round!(0)
    assert_equal [ 1, 1 ], result[:answer_counts]
    assert_equal 50, result[:previous_points][beto.id.to_s]
    assert_equal @ana.id.to_s, result[:new_leader]
  ensure
    beto&.delete
  end

  test "no new leader when the leader stays or it's a tie" do
    svc = GameServices::HowWantBeBillionare.new(@room)
    assert_nil svc.send(:new_leader, { "a" => 100, "b" => 0 }, { "a" => 200, "b" => 100 })
    assert_nil svc.send(:new_leader, { "a" => 100, "b" => 0 }, { "a" => 100, "b" => 100 })
    assert_nil svc.send(:new_leader, { "a" => 0 }, { "a" => 0 })
  end
end
