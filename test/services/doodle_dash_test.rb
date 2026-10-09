require "test_helper"

class DoodleDashTest < ActiveSupport::TestCase
  Doodle = GameServices::DoodleDash

  setup do
    @game = Game.create!(name: "Doodle Dash", code: "doodle_dash", description: "Draw")
    @room = Room.create!(game: @game, game_state: { "draw_time" => "60", "turns_per_player" => "2", "difficulty" => "easy" })
    @ana, @beto, @caro = %w[Ana Beto Caro].map { |n| @room.players.create!(nickname: n) }

    @svc = Doodle.new(@room)
    @svc.setup_game!
  end

  teardown do
    Player.where(room_id: @room.id).delete_all
    @room.delete
    @game.delete
  end

  # Each player's channel loads its own copy of the room.
  def svc
    Doodle.new(Room.find(@room.id))
  end

  def start_drawing(word_index = 0)
    turn = @svc.start_turn!(0)
    artist = Player.find(turn[:artist_id])
    word = svc.choose_word!(artist.id, word_index)
    [ artist, word, ([ @ana, @beto, @caro ] - [ artist ]) ]
  end

  test "setup reads the settings and lets everyone draw once per lap" do
    state = @room.reload.game_state
    assert_equal 60, state["draw_time"]
    assert_equal "easy", state["difficulty"]
    assert state["show_guesses"]
    assert_equal 6, state["turns"].length
    assert_equal state["turns"].first(3), state["turns"].last(3)
    assert_equal [ @ana, @beto, @caro ].map { |p| p.id.to_s }.sort, state["turns"].first(3).sort
  end

  test "bad settings fall back to the defaults, and the guess feed can be turned off" do
    @room.update!(game_state: { "draw_time" => "7", "turns_per_player" => "9", "difficulty" => "nope", "show_guesses" => "false" })
    Doodle.new(@room).setup_game!
    state = @room.reload.game_state

    assert_equal [ 80, 1, "mixed", false ], state.values_at("draw_time", "turns_per_player", "difficulty", "show_guesses")
  end

  test "a turn offers three different unused words of the chosen level" do
    choices = @svc.start_turn!(0)[:choices]
    assert_equal 3, choices.uniq.length
    assert(choices.all? { |w| Doodle::WORDS["en"]["easy"].include?(w) })
  end

  test "mixed offers one easy, one medium and one hard word" do
    @room.atomic_set("game_state.difficulty" => "mixed")
    easy, medium, hard = Doodle.new(@room).start_turn!(0)[:choices]

    assert_includes Doodle::WORDS["en"]["easy"], easy
    assert_includes Doodle::WORDS["en"]["medium"], medium
    assert_includes Doodle::WORDS["en"]["hard"], hard
  end

  test "only the artist can pick the word, and the first pick wins" do
    turn = @svc.start_turn!(0)
    artist = Player.find(turn[:artist_id])
    other  = ([ @ana, @beto, @caro ] - [ artist ]).first

    assert_nil svc.choose_word!(other.id, 0)
    assert_equal turn[:choices][1], svc.choose_word!(artist.id, 1)
    assert_nil svc.choose_word!(nil) # the loop's random pick comes too late

    state = @room.reload.game_state
    assert_equal "drawing", state["status"]
    assert_equal turn[:choices][1], state["word"]
    assert_equal [ turn[:choices][1] ], state["used_words"]
  end

  test "the TV and the guessers never get the word while it is being drawn" do
    artist, word, guessers = start_drawing
    room = Room.find(@room.id)

    [ Doodle.new(room).public_state, Doodle.new(room).host_state, Doodle.new(room).player_state(guessers.first.id) ].each do |shown|
      assert_not shown.key?("word")
      assert_not shown.key?("choices")
    end
    assert_equal word, Doodle.new(room).player_state(artist.id)["word"]
    assert_equal word.length, room.game_state["pattern"].length
  end

  test "a correct guess scores by speed and pays the artist" do
    artist, word, (guesser, _) = start_drawing
    result = svc.guess!(guesser.id, word.upcase)

    assert_equal "correct", result[:result]
    assert_equal 100, result[:points]
    scores = @room.reload.game_state["scores"]
    assert_equal 100, scores[guesser.id.to_s]
    assert_equal Doodle::ARTIST_POINTS, scores[artist.id.to_s]

    assert_equal({ ok: false }, svc.guess!(guesser.id, word)) # only once
    assert_equal({ ok: false }, svc.guess!(artist.id, word))  # not the artist
  end

  test "a late guess scores less, never under 50" do
    _artist, word, (guesser, other) = start_drawing
    @room.atomic_set("game_state.turn_ends_at" => Time.now.to_f + 30) # half the 60s left
    assert_equal 75, svc.guess!(guesser.id, word)[:points]

    @room.atomic_set("game_state.turn_ends_at" => Time.now.to_f - 5)
    assert_equal 50, svc.guess!(other.id, word)[:points]
  end

  test "guess matching ignores case, accents, spaces, punctuation, articles and plurals" do
    assert Doodle.correct?("  Hot-Dog! ", "hot dog")
    assert Doodle.correct?("hotdog", "hot dog")
    assert Doodle.correct?("the cats", "cat")
    assert Doodle.correct?("Déjà vu", "deja vu")
    assert Doodle.correct?("writers block", "writer's block")
    assert_not Doodle.correct?("dog", "cat")
    assert_not Doodle.correct?("!!!", "cat")
  end

  test "one letter off is close on longer words only" do
    assert Doodle.close?("pengun", "penguin")
    assert Doodle.close?("rainbaw", "rainbow")
    assert Doodle.close?("pengiun", "penguin") # swapped neighbours
    assert_not Doodle.close?("cap", "cat")
    assert_not Doodle.close?("pigeon", "penguin")
  end

  test "close and wrong guesses don't score" do
    _artist, _word, (guesser, _) = start_drawing
    @room.atomic_set("game_state.word" => "penguin")

    assert_equal "close", svc.guess!(guesser.id, "pengiun")[:result]
    assert_equal({ ok: true, result: "wrong", text: "a big fish" }, svc.guess!(guesser.id, "a big  fish"))
    assert_equal 0, @room.reload.game_state["scores"][guesser.id.to_s]
  end

  test "rude wrong guesses are masked in the TV feed" do
    assert_equal "***", Doodle.feed_text("you SHITHEAD")
    assert_equal "***", Doodle.feed_text("ass")
    assert_equal "assemble a desk", Doodle.feed_text("assemble a desk")
    assert_equal "cockroach", Doodle.feed_text("cockroach")
  end

  test "hints reveal letters but always keep two hidden" do
    start_drawing
    @room.atomic_set("game_state.word" => "cat", "game_state.pattern" => [ nil, nil, nil ])

    pattern = svc.reveal_hint!
    assert_equal 1, pattern.compact.length
    assert_includes %w[c a t], pattern.compact.first
    assert_nil svc.reveal_hint!
  end

  test "the turn ends when every guesser has it" do
    _artist, word, guessers = start_drawing
    assert_not svc.all_guessed?

    guessers.each { |p| svc.guess!(p.id, word) }
    assert svc.all_guessed?

    reveal = svc.end_turn!
    assert_equal word, reveal[:word]
    assert_equal guessers.map { |p| p.id.to_s }.sort, reveal[:guessed].keys.sort
    assert_equal word, Doodle.new(Room.find(@room.id)).public_state["word"]
  end

  def stroke(id) = { "id" => id, "color" => "#111827", "size" => 10, "points" => [ [ 0.1, 0.2 ], [ 0.3, 0.4 ] ] }
  def saved_ids = @room.reload.game_state["strokes"].map { |s| s["id"] }

  test "only the drawing artist can save, undo and clear strokes" do
    artist, _word, (guesser, _) = start_drawing

    assert_not svc.save_stroke!(guesser.id, stroke(1))
    assert svc.save_stroke!(artist.id, stroke(1))
    assert svc.save_stroke!(artist.id, stroke(2))
    assert_not svc.save_stroke!(artist.id, stroke(2)) # saved once
    assert_not svc.undo!(guesser.id, 2)
    assert svc.undo!(artist.id, 2)
    assert_equal [ 1 ], saved_ids

    assert svc.clear!(artist.id, 1)
    assert_empty saved_ids
  end

  # Phone messages can be handled in any order: the drawing must end up the same.
  test "a stroke undone or cleared before it is saved is never saved" do
    artist, = start_drawing

    svc.undo!(artist.id, 3)
    assert_not svc.save_stroke!(artist.id, stroke(3))

    svc.clear!(artist.id, 5)
    assert_not svc.save_stroke!(artist.id, stroke(4))
    assert svc.save_stroke!(artist.id, stroke(6))
    assert_equal [ 6 ], saved_ids
  end

  test "a new turn starts with a blank drawing and fresh stroke ids" do
    artist, = start_drawing
    svc.save_stroke!(artist.id, stroke(1))
    svc.undo!(artist.id, 2)
    svc.clear!(artist.id, 1)

    @svc.start_turn!(1)
    state = @room.reload.game_state
    assert_equal [ [], [], 0 ], state.values_at("strokes", "removed_strokes", "cleared_upto")
  end

  test "points and styles from the phone are cleaned" do
    assert_equal [ [ 0.0, 1.0 ], [ 0.1235, 0.5 ] ], Doodle.clean_points([ [ -2, 9 ], [ 0.123456, 0.5 ] ])
    assert_nil Doodle.clean_points([ [ 0.1 ] ])
    assert_nil Doodle.clean_points([ [ "x", 0.1 ] ])
    assert_nil Doodle.clean_points(Array.new(Doodle::MAX_POINTS_PER_MESSAGE + 1) { [ 0.1, 0.1 ] })
    assert_nil Doodle.clean_style("#123456", 10)
    assert_nil Doodle.clean_style("#111827", 7)
    assert_equal({ "color" => "#111827", "size" => 24 }, Doodle.clean_style("#111827", 24))
  end

  test "a player who leaves is taken out of the turns to come, and ends their own turn" do
    turn   = @svc.start_turn!(0)
    artist = turn[:artist_id]
    other  = (@room.reload.game_state["turns"] - [ artist ]).first

    svc.player_removed!(other)
    turns = @room.reload.game_state["turns"]
    assert_equal 4, turns.length
    assert_not_includes turns, other
    assert_not @room.game_state["artist_left"]

    svc.player_removed!(artist)
    state = @room.reload.game_state
    assert state["artist_left"]
    assert_equal artist, state["turns"].first # the turn being played stays in the list
    assert_equal 3, state["turns"].length    # [artist, third player, third player]
  end

  test "a turn whose artist has left is skipped" do
    artist_id = @room.game_state["turns"].first
    Player.where(_id: artist_id).delete_all

    assert_nil @svc.start_turn!(0)
  end

  test "a Spanish room draws Spanish words" do
    @room.update!(locale: "es")
    choices = Doodle.new(Room.find(@room.id)).send(:pick_words)
    assert(choices.all? { |w| Doodle::WORDS["es"]["easy"].include?(w) })
  end

  test "Spanish guesses: accents, articles and plurals don't matter" do
    assert Doodle.correct?("el camion", "camión")
    assert Doodle.correct?("camiones", "camión")
    assert Doodle.correct?("una flor", "flor")
    assert Doodle.correct?("flores", "flor")
    assert Doodle.correct?("arcoiris", "arcoíris")
    assert Doodle.close?("arcoirsi", "arcoíris")
    assert_not Doodle.correct?("perro", "gato")
  end

  test "every word list is complete, unique and never blocked on the TV" do
    Doodle::WORDS.each do |locale, levels|
      assert_equal %w[easy medium hard], levels.keys, locale
      levels.each do |level, words|
        assert_operator words.size, :>=, 80, "#{locale}.#{level}"
        assert_equal words.uniq, words, "#{locale}.#{level} has duplicates"
        assert(words.all? { |w| w == w.downcase }, "#{locale}.#{level} must be lowercase")
        blocked = words.select { |w| Doodle.feed_text(w) == "***" }
        assert_empty blocked, "#{locale}.#{level} words hidden by blocked_words.yml"
      end
    end
  end
end
