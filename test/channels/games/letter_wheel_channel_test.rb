require "test_helper"

class Games::LetterWheelChannelTest < ActionCable::Channel::TestCase
  Wheel = GameServices::LetterWheel

  setup do
    @game = Game.create!(name: "Letter Wheel", code: "letter_wheel", description: "Clues")
    @room = Room.create!(game: @game, game_state: { "word_time" => "10" })
    @ana  = @room.players.create!(nickname: "Ana")
    Wheel.new(@room).setup_game!
  end

  teardown do
    Player.where(room_id: @room.id).delete_all
    Event.where(room_id: @room.id).delete_all
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

  def fast(&)
    with_constants(Games::LetterWheelChannel, REVEAL_DURATION: 0.05, GRACE_PERIOD: 0, EARLY_END_DELAY: 0, POLL_INTERVAL: 0.02, &)
  end

  def room_stream = "letter_wheel_room_#{@room.code}"
  def messages = broadcasts(room_stream).map { JSON.parse(_1) }
  def phases = messages.filter_map { _1.dig("state", "phase") }
  def state = @room.reload.game_state
  def svc = Wheel.new(Room.find(@room.id))

  def wait_until(seconds = 8)
    Timeout.timeout(seconds) { sleep 0.02 until yield }
  end

  test "a whole game: every letter, right answers count and the room finishes" do
    @room.atomic_set("game_state.words" => state["words"].first(2), "game_state.letters" => state["letters"].first(2))

    fast do
      subscribe(room_code: @room.code, player_id: "")
      perform :start_game_loop

      [ 1, 2 ].each do |round|
        wait_until { state["round"] == round && state["phase"] == "clue" }
        svc.answer!(@ana.id, svc.current_word["answer"])
        wait_until { state["round"] != round || %w[reveal game_over].include?(state["phase"]) }
      end
      wait_until { phases.include?("game_over") }
    end

    assert_equal "finished", @room.reload.status
    assert_equal 2, state["correct"][@ana.id.to_s]
    assert_equal %w[clue reveal game_over], phases.uniq
    clues = messages.select { _1.dig("state", "phase") == "clue" }
    assert(clues.none? { _1["state"].key?("answer") })
  end

  test "a second TV connection doesn't start a second loop, and Play Again stops the old one" do
    fast do
      subscribe(room_code: @room.code, player_id: "")
      perform :start_game_loop
      wait_until { state["phase"] == "clue" }
      old_loop = state["loop_id"]

      perform :start_game_loop
      assert_equal old_loop, state["loop_id"]

      perform :restart_game
      assert_nil state["loop_id"]
      assert_equal "waiting", state["phase"]
      sleep 0.2
      assert_equal "waiting", state["phase"]
    end
  end

  test "the phone hears right or wrong; every screen hears that it answered" do
    svc.start_round!(1)
    subscribe(room_code: @room.code, player_id: @ana.id.to_s)

    perform :answer, text: ""
    assert_empty messages

    perform :answer, text: svc.current_word["answer"]
    assert_equal [ { "action" => "answered", "player_id" => @ana.id.to_s } ], messages
    assert_equal "answer_result", transmissions.last["action"]
    assert transmissions.last["right"]
  end

  test "only the host can start or restart" do
    subscribe(room_code: @room.code, player_id: @ana.id.to_s)
    perform :start_game_loop
    perform :restart_game
    assert_nil state["loop_id"]
    assert_empty messages
  end
end
