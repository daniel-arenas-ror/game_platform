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
end
