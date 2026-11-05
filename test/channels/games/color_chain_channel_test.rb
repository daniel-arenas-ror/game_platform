require "test_helper"

class Games::ColorChainChannelTest < ActionCable::Channel::TestCase
  Chain = GameServices::ColorChain

  setup do
    @game = Game.create!(name: "Color Chain", code: "color_chain", description: "Repeat")
    @room = Room.create!(game: @game, game_state: { "start_length" => "2", "total_rounds" => "5" })
    @ana  = @room.players.create!(nickname: "Ana")
    Chain.new(@room).setup_game!
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
    with_constants(Chain, LEAD_IN: 0.01, FLASH_DURATION: 0.01, FLASH_GAP: 0) do
      with_constants(Games::ColorChainChannel, REVEAL_DURATION: 0.05, GRACE_PERIOD: 0, EARLY_END_DELAY: 0, POLL_INTERVAL: 0.02, &)
    end
  end

  def room_stream = "color_chain_room_#{@room.code}"
  def host_stream = "#{room_stream}_host"
  def messages(stream = room_stream) = broadcasts(stream).map { JSON.parse(_1) }
  def phases = messages.filter_map { _1.dig("state", "phase") }
  def state = @room.reload.game_state
  def svc = Chain.new(Room.find(@room.id))

  def wait_until(seconds = 8)
    Timeout.timeout(seconds) { sleep 0.02 until yield }
  end

  test "the host streams the sequence; a phone doesn't" do
    subscribe(room_code: @room.code, player_id: "")
    assert_has_stream room_stream
    assert_has_stream host_stream
    assert_includes transmissions.last["state"].keys, "sequence"

    unsubscribe
    subscribe(room_code: @room.code, player_id: @ana.id.to_s)
    assert_has_stream room_stream
    assert_has_no_stream host_stream
    assert_not_includes transmissions.last["state"].keys, "sequence"
  end

  test "a whole game: rounds grow, answers score and the room finishes" do
    @room.atomic_set("game_state.total_rounds" => 2)

    fast do
      subscribe(room_code: @room.code, player_id: "")
      perform :start_game_loop

      [ 1, 2 ].each do |round|
        wait_until { state["round"] == round && state["phase"] == "input" }
        svc.answer!(@ana.id, svc.sequence)
        wait_until { state["round"] != round || %w[reveal game_over].include?(state["phase"]) }
      end
      wait_until { phases.include?("game_over") }
    end

    assert_equal "game_over", state["phase"]
    assert_equal 50, state["scores"][@ana.id.to_s] # 2 colours, then 3
    assert_equal [ 2, 3 ], messages(host_stream).map { _1["sequence"].length }
    assert_equal %w[watching input reveal game_over], phases.uniq
    phases_before_reveal = messages.select { %w[watching input].include?(_1.dig("state", "phase")) }
    assert(phases_before_reveal.none? { _1["state"].key?("sequence") })
  end

  test "a second TV connection doesn't start a second loop, and Play Again stops the old one" do
    fast do
      subscribe(room_code: @room.code, player_id: "")
      perform :start_game_loop
      wait_until { state["phase"] == "input" }
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

  test "an answer through the channel tells every screen; a bad one doesn't" do
    svc.start_round!(1)
    svc.start_input!
    subscribe(room_code: @room.code, player_id: @ana.id.to_s)

    perform :answer, colors: %w[purple]
    assert_empty messages

    perform :answer, colors: svc.sequence
    assert_equal [ { "action" => "answered", "player_id" => @ana.id.to_s } ], messages
  end

  test "only the host can start or restart" do
    subscribe(room_code: @room.code, player_id: @ana.id.to_s)
    perform :start_game_loop
    perform :restart_game
    assert_nil state["loop_id"]
    assert_empty messages
  end
end
