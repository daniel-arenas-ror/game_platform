require "test_helper"

class LetterWheelTest < ActiveSupport::TestCase
  Wheel = GameServices::LetterWheel

  setup do
    @game = Game.create!(name: "Letter Wheel", code: "letter_wheel", description: "Clues")
    @room = Room.create!(game: @game, game_state: { "word_time" => "10", "length" => "short" })
    @ana, @beto = %w[Ana Beto].map { |n| @room.players.create!(nickname: n) }
    Wheel.new(@room).setup_game!
  end

  teardown do
    # Only this test's records: tests run in parallel against one database.
    Player.where(room_id: @room.id).delete_all
    Event.where(room_id: @room.id).delete_all
    @room.delete
    @game.delete
  end

  # Each player's channel loads its own copy of the room.
  def svc = Wheel.new(Room.find(@room.id))
  def state = @room.reload.game_state
  def answer = svc.current_word["answer"]
  def right?(guess, answer, locale = "en", also: []) = Wheel.right_answer?(guess, { "answer" => answer, "also" => also }, locale)

  test "every letter of both alphabets has clues at every level, and every answer fits its letter" do
    plain = ->(text) { text.unicode_normalize(:nfkd).gsub(/\p{Mn}/, "") }

    Wheel::ALPHABETS.each do |locale, alphabet|
      Wheel::WORDS[locale].each do |level, list|
        assert_equal alphabet.sort, list.keys.sort, "#{locale} #{level} letters"
        list.each do |letter, words|
          assert words.size >= 5, "#{locale} #{level} #{letter}: at least 5 clues, so games don't repeat"
          words.each do |w|
            assert w["clue"].present?, "#{locale} #{level} #{letter}: clue"
            word = w["answer"].downcase
            fits = w["contains"] ? word.include?(letter) : plain.(word).start_with?(plain.(letter))
            fits &&= word.include?(letter) if letter == "ñ"
            assert fits, "#{locale} #{level} #{letter}: #{w["answer"]}"
            assert_not_includes w["clue"].downcase, word, "#{locale} #{level} #{letter}: the clue gives the answer away"
          end
        end
      end

      # Across levels too: a mixed game draws from both lists.
      answers = Wheel::WORDS[locale].values.flat_map { _1.values.flatten }.map { Wheel.comparable(_1["answer"], locale) }
      assert_empty answers.tally.select { |_, n| n > 1 }.keys, "#{locale}: the same answer twice"
    end
  end

  test "the level picks the list: everyday, general knowledge or both" do
    hard = ->(locale) { Wheel::WORDS[locale]["hard"].values.flatten.map { _1["answer"] } }
    easy = ->(locale) { Wheel::WORDS[locale]["easy"].values.flatten.map { _1["answer"] } }

    assert_equal "easy", state["level"]
    assert_empty state["words"].map { _1["answer"] } - easy.("en")

    @room.atomic_set("game_state.level" => "hard")
    Wheel.new(@room).setup_game!
    assert_empty state["words"].map { _1["answer"] } - hard.("en")

    picked = 20.times.flat_map { Wheel.pick_words("es", "full", "mix").map { _1["answer"] } }
    assert_empty picked - hard.("es") - easy.("es")
    assert(picked.intersect?(hard.("es")) && picked.intersect?(easy.("es")), "a mix draws from both")

    @room.atomic_set("game_state.level" => "impossible")
    Wheel.new(@room).setup_game!
    assert_equal "easy", state["level"]
  end

  test "reads the settings, falls back on values it doesn't offer, and keeps the letters in order" do
    assert_equal [ 10, "short", Wheel::SHORT_LETTERS ], [ state["word_time"], state["length"], state["letters"].size ]
    assert_equal state["letters"].sort_by { Wheel::ALPHABETS["en"].index(_1) }, state["letters"]

    @room.atomic_set("game_state.word_time" => "7", "game_state.length" => "full")
    Wheel.new(@room).setup_game!
    assert_equal [ 20, Wheel::ALPHABETS["en"] ], [ state["word_time"], state["letters"] ]

    @room.atomic_set("game_state.length" => "huge")
    Wheel.new(@room).setup_game!
    assert_equal "short", state["length"]
  end

  test "a Spanish room gets the Spanish alphabet, with Ñ" do
    @room.update!(locale: "es")
    @room.atomic_set("game_state.length" => "full")
    Wheel.new(@room).setup_game!
    assert_equal 27, state["letters"].size
    assert_equal "ñ", state["letters"][14]
    assert_includes state["words"][14]["answer"], "ñ"
  end

  test "answers match without accents, case, articles or plurals, and forgive one typo on long words" do
    assert right?("Elephant", "elephant")
    assert right?("the elephants!", "elephant")
    assert right?("elephnt", "elephant"), "one letter missing"
    assert right?("yoghurt", "yogurt", also: [ "yoghurt" ])
    assert right?("el avion", "avión", "es")
    assert right?("las arañas", "araña", "es")
    assert right?("ARANA", "araña", "es")

    assert_not right?("", "elephant")
    assert_not right?("elk", "elephant")
    assert_not right?("eleffant", "elephant"), "two typos"
    assert_not right?("cat", "car"), "short words must be exact"
    assert_not right?("the", "theatre")
  end

  test "points: base plus a speed bonus that runs out with the time" do
    assert_equal 200, Wheel.points_for(10, 10)
    assert_equal 150, Wheel.points_for(5, 10)
    assert_equal 100, Wheel.points_for(0, 10)
    assert_equal 100, Wheel.points_for(-2, 10)
  end

  test "a right answer scores at once on the phone and counts as a word at the reveal" do
    svc.start_round!(1)
    result = svc.answer!(@ana.id, answer)
    assert result["right"]
    assert_operator result["points"], :>, 190
    assert_equal({ "right" => false, "points" => 0 }, svc.answer!(@beto.id, "zzzz"))

    assert svc.score_round!
    assert_equal "reveal", state["phase"]
    assert_equal [ result["points"], 0 ], [ state["scores"][@ana.id.to_s], state["scores"][@beto.id.to_s] ]
    assert_equal [ 1, 0 ], [ state["correct"][@ana.id.to_s], state["correct"][@beto.id.to_s] ]
    assert_equal 0.5, state["results"][state["letters"].first]
  end

  test "one try per player, only while the clue is up, and a blank doesn't use it" do
    assert_nil svc.answer!(@ana.id, answer), "the game hasn't started a word"

    svc.start_round!(1)
    assert_nil svc.answer!(@ana.id, "   ")
    assert_not_nil svc.answer!(@ana.id, "wrong")
    assert_nil svc.answer!(@ana.id, answer), "second try"
    assert_nil svc.answer!(BSON::ObjectId.new, answer), "not in this game"

    svc.score_round!
    assert_nil svc.answer!(@beto.id, answer), "too late"
    assert_not svc.score_round!, "scored twice"
  end

  test "all_answered? also holds when the last waiting player is removed" do
    svc.start_round!(1)
    svc.answer!(@ana.id, answer)
    assert_not svc.all_answered?

    PlayerRemover.new(@beto).remove!
    assert svc.all_answered?
  end

  test "a player who joins during the game can answer and keeps their points on a repeat join" do
    late = @room.players.create!(nickname: "Caro")
    assert svc.join!(late.id)
    svc.start_round!(1)
    assert svc.answer!(late.id, answer)["right"]
    svc.score_round!

    assert_not svc.join!(late.id)
    assert_equal 1, state["correct"][late.id.to_s]
  end

  test "the most words wins; points only break ties" do
    s = { "scores" => { "a" => 300, "b" => 500, "c" => 400 }, "correct" => { "a" => 3, "b" => 2, "c" => 2 } }
    assert_equal %w[a b c], Wheel.ranking(s)
  end

  test "screens never see the answer before the reveal" do
    svc.start_round!(1)
    shown = svc.public_state
    assert_equal [ state["letters"].first, svc.current_word["clue"] ], [ shown["letter"], shown["clue"] ]
    assert_empty shown.keys & %w[words answers answer guesses loop_id]
    assert_not_includes shown.to_json, answer

    svc.answer!(@ana.id, answer)
    assert_equal [ @ana.id.to_s ], svc.public_state["answered"]
    assert_not_includes svc.public_state.to_json, answer, "a right guess doesn't leak it either"

    svc.score_round!
    shown = svc.public_state
    assert_equal answer, shown["answer"]
    assert_equal({ "text" => answer, "right" => true }, shown["guesses"][@ana.id.to_s])

    svc.finish_game!
    shown = svc.public_state
    assert_equal state["letters"], shown["solutions"].map { _1["letter"] }
    assert_equal @ana.id.to_s, shown["ranking"].first
  end
end
