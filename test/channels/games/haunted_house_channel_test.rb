require "test_helper"

class Games::HauntedHouseChannelTest < ActionCable::Channel::TestCase
  House = GameServices::HauntedHouse

  setup do
    @game = Game.create!(name: "Haunted House", code: "haunted_house", description: "Boo")
    @room = Room.create!(game: @game, game_state: {})
    @ana, @beto, @caro, @dani = %w[Ana Beto Caro Dani].map { |n| @room.players.create!(nickname: n) }
    House.new(@room).setup_game!
    # Fixed roles: Ana is the ghost, Beto the Medium, Caro and Dani trick-or-treaters.
    @room.atomic_set("game_state.roles" => { @ana.id.to_s => "ghost", @beto.id.to_s => "medium",
                                             @caro.id.to_s => "guest", @dani.id.to_s => "guest" },
                     "game_state.discussion_time" => 30)
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
    with_constants(Games::HauntedHouseChannel, ROLES_DURATION: 0.1, NIGHT_DURATION: 5, MORNING_DURATION: 0.1,
                   VOTE_DURATION: 5, VERDICT_DURATION: 0.1, GRACE_PERIOD: 0, EARLY_END_DELAY: 0, POLL_INTERVAL: 0.02, &)
  end

  def room_stream = "haunted_house_room_#{@room.code}"
  def host_stream = "haunted_house_room_#{@room.code}_host"
  def player_stream(player) = "haunted_house_room_#{@room.code}_player_#{player.id}"
  def messages(stream) = broadcasts(stream).map { JSON.parse(_1) }
  def phases = messages(host_stream).filter_map { _1.dig("state", "phase") }
  def svc = House.new(Room.find(@room.id))

  def wait_until(seconds = 5)
    Timeout.timeout(seconds) { sleep 0.02 until yield }
  end

  test "the TV gets no roles; a phone gets its own role on its own stream" do
    subscribe(room_code: @room.code, player_id: "")
    assert_has_stream host_stream
    assert_nil transmissions.last.dig("state", "roles")
    assert_nil transmissions.last.dig("state", "my_role")
    unsubscribe

    subscribe(room_code: @room.code, player_id: @caro.id.to_s)
    assert_has_stream player_stream(@caro)
    assert_has_no_stream host_stream
    assert_equal "guest", transmissions.last.dig("state", "my_role")
    assert_equal({ @ana.id.to_s => "Ana", @beto.id.to_s => "Beto", @caro.id.to_s => "Caro", @dani.id.to_s => "Dani" },
                 transmissions.last["nicknames"])
  end

  test "a whole game: the night ends once everyone acts, the vote once everyone votes" do
    fast do
      subscribe(room_code: @room.code, player_id: "")
      perform :start_game_loop

      wait_until { phases.include?("night") }
      svc.ghost_pick!(@ana.id, @caro.id)
      svc.medium_check!(@beto.id, @ana.id)
      svc.hide!(@caro.id, "attic")
      svc.hide!(@dani.id, "garden")

      wait_until { phases.include?("discussion") }
      morning = messages(host_stream).find { _1.dig("state", "phase") == "morning" }["state"]
      assert_equal({ "id" => @caro.id.to_s, "place" => "attic" }, morning["victim"])
      perform :skip_discussion

      wait_until { phases.include?("vote") }
      [ @ana, @beto, @dani ].each { |p| svc.vote!(p.id, @ana.id) unless p == @ana }
      svc.vote!(@ana.id, @dani.id)

      wait_until { phases.include?("game_over") }
      assert_equal %w[roles night morning discussion vote verdict game_over], phases.uniq
      over = messages(host_stream).last["state"]
      assert_equal "guests", over["winner"]
      assert_equal [ @beto, @caro, @dani ].map { _1.id.to_s }.sort, over["winners"].sort
      assert_equal "ghost", over["roles"][@ana.id.to_s]
      assert_equal "finished", @room.reload.status

      # Each phone was sent its own view of every phase.
      assert_equal "medium", messages(player_stream(@beto)).last.dig("state", "my_role")
    end
  end

  test "ghosts win at night when they're as many as everyone else" do
    @room.atomic_set("game_state.alive" => [ @ana, @caro, @dani ].map { _1.id.to_s })
    fast do
      subscribe(room_code: @room.code, player_id: "")
      perform :start_game_loop

      wait_until { phases.include?("night") }
      svc.ghost_pick!(@ana.id, @caro.id)
      svc.hide!(@caro.id, "attic")
      svc.hide!(@dani.id, "attic")

      wait_until { phases.include?("game_over") }
      assert_equal %w[roles night morning game_over], phases.uniq
      assert_equal "ghosts", messages(host_stream).last.dig("state", "winner")
    end
  end

  test "the ghost's pick goes to the ghosts only, and everyone sees who has acted" do
    svc.start_night!(30)
    subscribe(room_code: @room.code, player_id: @ana.id.to_s)
    perform :ghost_pick, "target_id" => @caro.id.to_s

    assert_equal({ @ana.id.to_s => @caro.id.to_s }, messages(player_stream(@ana)).last["ghost_picks"])
    assert_empty messages(player_stream(@caro))
    assert_equal [ @ana.id.to_s ], messages(room_stream).last["acted"]
    assert_not(messages(room_stream).last.key?("ghost_picks"))
  end

  test "the Medium learns at once; a hiding player hears back; nobody else hears either" do
    svc.start_night!(30)
    subscribe(room_code: @room.code, player_id: @beto.id.to_s)
    perform :medium_check, "target_id" => @ana.id.to_s
    assert_equal [ "medium_result", @ana.id.to_s, true ], transmissions.last.values_at("action", "target_id", "ghost")
    unsubscribe

    subscribe(room_code: @room.code, player_id: @caro.id.to_s)
    perform :hide, "place" => "library"
    assert_equal [ "hidden", "library" ], transmissions.last.values_at("action", "place")
    assert(messages(room_stream).none? { _1.key?("ghost") || _1.key?("place") })
  end

  test "votes come back to the voter, and the room sees who has voted" do
    svc.start_vote!(30)
    subscribe(room_code: @room.code, player_id: @caro.id.to_s)
    perform :vote, "target_id" => @ana.id.to_s

    assert_equal [ "voted", @ana.id.to_s ], transmissions.last.values_at("action", "target_id")
    assert_equal [ @caro.id.to_s ], messages(room_stream).last["acted"]
  end

  test "players can't run the loop, skip or restart" do
    subscribe(room_code: @room.code, player_id: @caro.id.to_s)
    perform :start_game_loop
    perform :restart_game
    assert_nil @room.reload.game_state["loop_id"]
    assert_empty messages(room_stream)
  end

  test "one loop per game, even when the TV reloads; a dead loop is taken over" do
    subscribe(room_code: @room.code, player_id: "")
    perform :start_game_loop
    first = @room.reload.game_state["loop_id"]
    assert first

    perform :start_game_loop # the TV reloaded while the loop runs
    assert_equal first, @room.reload.game_state["loop_id"]

    @room.atomic_set("game_state.loop_beat" => Time.now.to_f - 60) # e.g. the server restarted
    perform :start_game_loop
    assert_not_equal first, @room.reload.game_state["loop_id"]
  ensure
    perform :restart_game # stops the loop
  end

  test "Play Again deals new roles and stops the old loop" do
    fast do
      subscribe(room_code: @room.code, player_id: "")
      perform :start_game_loop
      wait_until { phases.include?("night") }

      perform :restart_game
      assert_equal "game_restarted", messages(room_stream).last["action"]
      assert_equal [ "waiting", nil ], @room.reload.game_state.values_at("phase", "loop_id")
      sleep 0.2
      assert_equal "waiting", @room.reload.game_state["phase"] # the old loop didn't carry on
    end
  end
end
