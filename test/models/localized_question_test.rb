require "test_helper"

# Rooms get questions in their own language (Billionaire and The Fisherman share LocalizedQuestion).
class LocalizedQuestionTest < ActiveSupport::TestCase
  setup do
    @billionaire = HowWantBeBillionare::Question.create!(text: "¿Pregunta #{SecureRandom.hex(3)}?", points: 100, topic: "T", locale: "es",
                                                          answers: [ { text: "Sí", correct: true }, { text: "No", correct: false } ])
    @fisherman   = Fisherman::Question.create!(text: "¿Qué #{SecureRandom.hex(3)}?", answerds: [ "Uno", "Dos" ], locale: "es")
    @game = Game.create!(name: "Billionaire", code: "how_want_be_billionare", description: "x")
    @room = Room.create!(game: @game, locale: "es", game_state: { "total_rounds" => 3, "time_per_round" => 20 })
    @room.players.create!(nickname: "Ana")
  end

  teardown do
    Player.where(room_id: @room.id).delete_all
    [ @room, @game, @billionaire, @fisherman ].each(&:delete)
  end

  test "a Spanish room only gets Spanish trivia questions" do
    3.times do
      GameServices::HowWantBeBillionare.new(@room.reload).setup_game!
      # Other tests run in parallel and may delete their own Spanish question meanwhile, so check
      # that no English question was picked rather than looking the question up.
      id = @room.reload.game_state["question_id"]
      assert_not HowWantBeBillionare::Question.where(:_id => id, :locale.ne => "es").exists?
    end
  end

  test "a Spanish Fisherman room only gets Spanish questions" do
    @room.players.create!(nickname: "Beto")
    @room.players.create!(nickname: "Caro")
    @game.update!(code: "fisherman")
    GameServices::Fisherman.new(@room.reload).setup_game!
    assert_not Fisherman::Question.where(text: @room.reload.game_state["question"], :locale.ne => "es").exists?
  end

  test "questions without a locale are English, and a language with none falls back to English" do
    english = { "locale" => { "$in" => [ nil, "en" ] } }
    assert_equal english, HowWantBeBillionare::Question.match_for("en")
    assert_equal({ "locale" => "es" }, HowWantBeBillionare::Question.match_for("es"))
    assert_equal english, Fisherman::Question.match_for("fr")
  end

  test "every Spanish question file matches its English one" do
    Dir[Rails.root.join("db/questions/how_want_be_billionare/*.yml")].each do |en_file|
      es_file = en_file.sub("how_want_be_billionare/", "how_want_be_billionare/es/")
      en, es = YAML.load_file(en_file), YAML.load_file(es_file)
      assert_equal en.size, es.size, File.basename(es_file)
      en.zip(es).each do |e, s|
        assert_equal e["points"], s["points"], s["text"]
        assert_equal e["answers"].map { |a| a["correct"] == true }, s["answers"].map { |a| a["correct"] == true }, s["text"]
      end
    end

    en, es = %w[en es].map { |l| YAML.load_file(Rails.root.join("db/questions/fisherman/#{l}.yml")) }
    assert_equal en.size, es.size
  end
end
