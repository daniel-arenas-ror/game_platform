require "test_helper"

class Games::DoodleDashChannelTest < ActionCable::Channel::TestCase
  setup do
    @game = Game.create!(name: "Doodle Dash", code: "doodle_dash", description: "Draw")
    @room = Room.create!(game: @game, game_state: { "difficulty" => "easy" })
    @ana, @beto = %w[Ana Beto].map { |n| @room.players.create!(nickname: n) }

    svc = GameServices::DoodleDash.new(@room)
    svc.setup_game!
    turn = svc.start_turn!(0)
    @artist  = Player.find(turn[:artist_id])
    @guesser = ([ @ana, @beto ] - [ @artist ]).first
    @word    = GameServices::DoodleDash.new(Room.find(@room.id)).choose_word!(@artist.id, 0)
  end

  teardown do
    Player.where(room_id: @room.id).delete_all
    @room.delete
    @game.delete
  end

  # Shrinks the game's timers for one test.
  def with_constants(mod, **values)
    old = values.to_h { |name, _| [ name, mod.const_get(name) ] }
    silence_warnings { values.each { |name, value| mod.const_set(name, value) } }
    yield
  ensure
    silence_warnings { old.each { |name, value| mod.const_set(name, value) } }
  end

  def host_stream = "doodle_dash_room_#{@room.code}_host"
  def room_stream = "doodle_dash_room_#{@room.code}"

  test "the TV streams the drawing, phones get only their own private stream" do
    subscribe(room_code: @room.code, player_id: "")
    assert_has_stream host_stream
    assert_not transmissions.last["state"].key?("word")

    unsubscribe
    subscribe(room_code: @room.code, player_id: @guesser.id.to_s)
    assert_has_no_stream host_stream
    assert_has_stream "doodle_dash_room_#{@room.code}_player_#{@guesser.id}"
    assert_not transmissions.last["state"].key?("word")

    unsubscribe
    subscribe(room_code: @room.code, player_id: @artist.id.to_s)
    assert_equal @word, transmissions.last["state"]["word"]
  end

  test "sync re-sends the artist's words from the current state" do
    subscribe(room_code: @room.code, player_id: @artist.id.to_s)
    assert_equal "drawing", transmissions.last["state"]["status"]
    # The state moves on after subscribing: the same artist gets new words.
    choices = GameServices::DoodleDash.new(Room.find(@room.id)).start_turn!(0)[:choices]

    perform :sync
    state = transmissions.last["state"]
    assert_equal "choosing", state["status"]
    assert_equal choices, state["choices"]
  end

  test "the artist's strokes go to the TV, and finished strokes are kept" do
    subscribe(room_code: @room.code, player_id: @artist.id.to_s)

    assert_broadcast_on(host_stream, action: "draw", start: true, points: [ [ 0.1, 0.2 ] ], color: "#111827", size: 10) do
      perform :draw, points: [ [ 0.1, 0.2 ] ], color: "#111827", size: 10, start: true
    end
    perform :draw, points: [ [ 0.3, 0.4 ] ], color: "#111827", size: 10
    perform :stroke_end

    stroke = @room.reload.game_state["strokes"].first
    assert_equal [ [ 0.1, 0.2 ], [ 0.3, 0.4 ] ], stroke["points"]
  end

  test "a guesser can't draw" do
    subscribe(room_code: @room.code, player_id: @guesser.id.to_s)

    assert_no_broadcasts(host_stream) do
      perform :draw, points: [ [ 0.1, 0.2 ] ], color: "#111827", size: 10, start: true
    end
  end

  test "a correct guess is answered privately and announced to the room without the word" do
    subscribe(room_code: @room.code, player_id: @guesser.id.to_s)

    assert_broadcasts(room_stream, 1) { perform :guess, text: @word }
    assert_equal({ "action" => "guess_result", "result" => "correct", "points" => 100, "word" => @word },
                 transmissions.last.slice("action", "result", "points", "word"))
    assert_not broadcasts(room_stream).last.include?(@word)
  end

  test "the game loop plays every turn, picks a word when the artist doesn't, and ends the game" do
    GameServices::DoodleDash.new(@room).setup_game!
    @room.atomic_set("game_state.draw_time" => 1)

    with_constants(Games::DoodleDashChannel, START_DELAY: 0, REVEAL_DURATION: 0, GRACE_PERIOD: 0.1, POLL_INTERVAL: 0.05) do
      with_constants(GameServices::DoodleDash, CHOOSE_TIME: 0.2) do
        subscribe(room_code: @room.code, player_id: "")
        perform :start_game_loop
        perform :start_game_loop # a second loop is refused

        Timeout.timeout(10) { sleep 0.1 until @room.reload.status == "finished" }
      end
    end

    actions = broadcasts(room_stream).map { |b| JSON.parse(b)["action"] }
    assert_equal 2, actions.count("drawing")
    assert_equal 2, actions.count("turn_over")
    assert_equal "game_over", actions.last
    assert_equal 2, @room.game_state["used_words"].length
  end

  test "wrong guesses go to the TV feed only when the host allows it" do
    subscribe(room_code: @room.code, player_id: @guesser.id.to_s)

    assert_broadcast_on(host_stream, action: "feed", player_id: @guesser.id.to_s, kind: "wrong", text: "zzz") do
      perform :guess, text: "zzz"
    end

    @room.atomic_set("game_state.show_guesses" => false)
    sleep Games::DoodleDashChannel::GUESS_COOLDOWN
    assert_no_broadcasts(host_stream) { perform :guess, text: "yyy" }
  end
end
