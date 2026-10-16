require "test_helper"

class HauntedHouseTest < ActiveSupport::TestCase
  House = GameServices::HauntedHouse

  setup do
    @game = Game.create!(name: "Haunted House", code: "haunted_house", description: "Boo")
    @room = Room.create!(game: @game, game_state: { "discussion_time" => "60" })
    @ana, @beto, @caro, @dani, @eva = %w[Ana Beto Caro Dani Eva].map { |n| @room.players.create!(nickname: n) }
    House.new(@room).setup_game!
  end

  teardown do
    # Only this test's records: tests run in parallel against one database.
    Player.where(room_id: @room.id).delete_all
    Event.where(room_id: @room.id).delete_all
    @room.delete
    @game.delete
  end

  # Each player's channel loads its own copy of the room.
  def svc = House.new(Room.find(@room.id))
  def state = @room.reload.game_state

  # Fixed roles instead of the random deal: Ana is the ghost, Beto the Medium, the rest trick-or-treaters.
  def deal!(ghosts: [ @ana ], medium: @beto)
    roles = @room.players.to_h { |p| [ p.id.to_s, House::GUEST ] }
    ghosts.each { |g| roles[g.id.to_s] = House::GHOST }
    roles[medium.id.to_s] = House::MEDIUM if medium
    @room.atomic_set("game_state.roles" => roles)
  end

  def night!
    svc.start_night!(30)
  end

  def vote_phase!
    svc.start_vote!(30)
  end

  # ── Setup ────────────────────────────────────────────────────────────────

  test "setup deals one ghost and one Medium to five players, and reads the settings" do
    s = state
    assert_equal [ "waiting", 0, 60, true, true, 1 ], s.values_at("phase", "night", "discussion_time", "medium", "reveal_roles", "ghost_total")
    assert_equal({ "ghost" => 1, "medium" => 1, "guest" => 3 }, s["roles"].values.tally)
    assert_equal @room.players.map { |p| p.id.to_s }.sort, s["alive"].sort
  end

  test "bad settings fall back to the defaults, and the Medium can be left out" do
    @room.update!(game_state: { "discussion_time" => "7", "ghosts" => "9", "medium" => "false", "reveal_roles" => "false" })
    House.new(@room).setup_game!

    assert_equal [ 120, "auto", false, false ], state.values_at("discussion_time", "ghosts", "medium", "reveal_roles")
    assert_not_includes state["roles"].values, House::MEDIUM
  end

  test "ghosts are always fewer than everyone else" do
    assert_equal 1, House.ghost_count(4, "auto")
    assert_equal 1, House.ghost_count(7, "auto")
    assert_equal 2, House.ghost_count(8, "auto")
    assert_equal 1, House.ghost_count(4, "2") # 2 ghosts vs 2 would win at once
    assert_equal 2, House.ghost_count(5, "2")
    assert_equal 1, House.ghost_count(10, "1")
    assert_equal 1, House.ghost_count(3, "auto")
  end

  test "the Medium needs four players" do
    assert_not_includes House.deal(%w[a b c], 1, true).values, House::MEDIUM
    assert_includes House.deal(%w[a b c d], 1, true).values, House::MEDIUM
  end

  # ── Night ────────────────────────────────────────────────────────────────

  test "only a ghost can pick a victim, never another ghost, and may change their mind" do
    deal!
    night!

    assert_not svc.ghost_pick!(@caro.id, @dani.id)   # not a ghost
    assert_not svc.ghost_pick!(@ana.id, @ana.id)     # a ghost
    assert svc.ghost_pick!(@ana.id, @caro.id)
    assert svc.ghost_pick!(@ana.id, @dani.id)
    assert_equal({ @ana.id.to_s => @dani.id.to_s }, state["ghost_picks"])
  end

  test "the morning scares out the ghosts' victim and says where they hid" do
    deal!
    night!
    svc.ghost_pick!(@ana.id, @caro.id)
    svc.hide!(@caro.id, "attic")

    result = svc.end_night!
    assert_equal [ @caro.id.to_s, "attic", House::GUEST, nil ], result.values_at(:victim, :place, :role, :winner)
    assert_equal "morning", state["phase"]
    assert_not_includes state["alive"], @caro.id.to_s
    assert_equal [ [ @caro.id.to_s, 1, "scared" ] ], state["out"].map { |o| o.values_at("id", "night", "how") }
  end

  test "two ghosts who disagree leave it to chance between their picks; no pick, nobody is scared" do
    @eli, @fer, @gus = %w[Eli Fer Gus].map { |n| @room.players.create!(nickname: n) }
    House.new(@room.reload).setup_game!
    deal!(ghosts: [ @ana, @beto ], medium: nil)
    night!
    svc.ghost_pick!(@ana.id, @caro.id)
    svc.ghost_pick!(@beto.id, @dani.id)
    assert_includes [ @caro.id.to_s, @dani.id.to_s ], svc.end_night![:victim]

    night!
    assert_nil svc.end_night![:victim]
    assert_equal 7, state["alive"].size
  end

  test "the Medium checks one player a night and learns if they're a ghost" do
    deal!
    night!
    assert_nil svc.medium_check!(@caro.id, @ana.id)              # not the Medium
    assert_nil svc.medium_check!(@beto.id, @beto.id)             # themselves
    assert_equal({ ghost: true }, svc.medium_check!(@beto.id, @ana.id))
    assert_nil svc.medium_check!(@beto.id, @caro.id)             # once a night

    svc.end_night!
    night!
    assert_equal({ ghost: false }, svc.medium_check!(@beto.id, @caro.id))
    assert_equal [ true, false ], state["medium_checks"].values_at("1", "2").map { _1["ghost"] }
  end

  test "trick-or-treaters hide once a night, in a real place" do
    deal!
    night!
    assert_not svc.hide!(@ana.id, "attic")     # the ghost doesn't hide
    assert_not svc.hide!(@caro.id, "moon")
    assert svc.hide!(@caro.id, "attic")
    assert_not svc.hide!(@caro.id, "kitchen")
    assert_equal "attic", state["hides"][@caro.id.to_s]
  end

  test "the night is done when everyone still in the house has acted" do
    deal!
    night!
    svc.ghost_pick!(@ana.id, @caro.id)
    svc.medium_check!(@beto.id, @caro.id)
    %w[attic kitchen].zip([ @caro, @dani ]).each { |place, p| svc.hide!(p.id, place) }
    assert_not svc.night_done?
    assert_equal 4, svc.acted_tonight.size

    svc.hide!(@eva.id, "garden")
    assert svc.night_done?
  end

  test "nothing counts outside the night" do
    deal!
    assert_not svc.ghost_pick!(@ana.id, @caro.id) # still waiting
    vote_phase!
    assert_not svc.hide!(@caro.id, "attic")
    assert_nil svc.medium_check!(@beto.id, @ana.id)
  end

  # ── Day ──────────────────────────────────────────────────────────────────

  test "the most votes is out; everyone votes once, for someone else still in the house" do
    deal!
    vote_phase!
    assert_not svc.vote!(@caro.id, @caro.id)
    assert svc.vote!(@caro.id, @dani.id)
    assert_not svc.vote!(@caro.id, @eva.id) # the first vote counts
    svc.vote!(@ana.id, @dani.id)
    svc.vote!(@dani.id, @ana.id)
    assert_not svc.all_voted?

    result = svc.end_vote!
    assert_equal [ @dani.id.to_s, House::GUEST, nil ], result.values_at(:out, :role, :winner)
    assert_equal({ @dani.id.to_s => 2, @ana.id.to_s => 1 }, result[:tally])
    assert_equal "verdict", state["phase"]
    assert_equal @dani.id.to_s, state["verdict"]["out"]
  end

  test "a tie, or no votes, and nobody is out" do
    deal!
    vote_phase!
    svc.vote!(@caro.id, @dani.id)
    svc.vote!(@dani.id, @caro.id)
    assert_nil svc.end_vote![:out]

    vote_phase!
    assert_nil svc.end_vote![:out]
    assert_equal 5, state["alive"].size
  end

  test "players who are out can't vote or be voted for" do
    deal!
    night!
    svc.ghost_pick!(@ana.id, @caro.id)
    svc.end_night!
    vote_phase!

    assert_not svc.vote!(@caro.id, @ana.id)
    assert_not svc.vote!(@dani.id, @caro.id)
  end

  # ── Winning ──────────────────────────────────────────────────────────────

  test "who wins" do
    roles = { "g" => House::GHOST, "m" => House::MEDIUM, "a" => House::GUEST, "b" => House::GUEST }
    assert_equal "guests", House.winner(roles, %w[m a b])
    assert_equal "ghosts", House.winner(roles, %w[g a])
    assert_nil House.winner(roles, %w[g a b])
  end

  test "voting the last ghost out wins it for the trick-or-treaters, all of them" do
    deal!
    vote_phase!
    [ @beto, @caro, @dani ].each { |p| svc.vote!(p.id, @ana.id) }

    assert_equal "guests", svc.end_vote![:winner]
    assert_equal "guests", svc.winner
    assert_equal [ @beto, @caro, @dani, @eva ].map { |p| p.id.to_s }.sort, svc.winners.sort
  end

  test "ghosts win when they're as many as everyone else" do
    deal!
    @room.atomic_set("game_state.alive" => [ @ana, @caro, @dani ].map { |p| p.id.to_s })
    night!
    svc.ghost_pick!(@ana.id, @caro.id)

    assert_equal "ghosts", svc.end_night![:winner]
    assert_equal [ @ana.id.to_s ], svc.winners
  end

  test "the ghost leaving the room ends it for the trick-or-treaters" do
    deal!
    night!
    @room.update!(status: "playing")
    PlayerRemover.new(@ana).remove!

    assert_equal "guests", state["winner"]
    assert_not_includes state["alive"], @ana.id.to_s
    assert_equal "left", state["out"].last["how"]
  end

  test "a player leaving at night doesn't hold the night up" do
    deal!
    night!
    @room.update!(status: "playing")
    svc.ghost_pick!(@ana.id, @caro.id)
    svc.medium_check!(@beto.id, @caro.id)
    [ @caro, @dani ].each { |p| svc.hide!(p.id, "attic") }
    PlayerRemover.new(@eva).remove!

    assert svc.night_done?
  end

  # ── Privacy ──────────────────────────────────────────────────────────────

  test "the TV sees no roles or picks while the game is on" do
    deal!
    night!
    svc.ghost_pick!(@ana.id, @caro.id)
    svc.hide!(@caro.id, "attic")
    shown = House.new(@room.reload).public_state

    assert_empty shown.keys & House::SECRET_KEYS
    assert_equal [ @ana.id.to_s, @caro.id.to_s ].sort, shown["acted"].sort
  end

  test "each phone sees its own role; a ghost also sees the ghosts and their picks" do
    deal!(ghosts: [ @ana, @caro ])
    night!
    svc.ghost_pick!(@caro.id, @dani.id)
    house = House.new(@room.reload)

    ghost = house.player_state(@ana.id)
    assert_equal House::GHOST, ghost["my_role"]
    assert_equal [ @ana.id.to_s, @caro.id.to_s ].sort, ghost["ghost_team"].sort
    assert_equal({ @caro.id.to_s => @dani.id.to_s }, ghost["ghost_picks"])

    guest = house.player_state(@dani.id)
    assert_equal House::GUEST, guest["my_role"]
    assert_nil guest["ghost_team"]
    assert_nil guest["ghost_picks"]
    assert_empty guest.keys & House::SECRET_KEYS
  end

  test "the roles of players who are out show only when the room reveals them, and all at the end" do
    @room.atomic_set("game_state.reveal_roles" => false)
    deal!
    night!
    svc.ghost_pick!(@ana.id, @caro.id)
    assert_nil svc.end_night![:role]
    assert_nil House.new(@room.reload).public_state["out"].first["role"]

    vote_phase!
    [ @beto, @dani, @eva ].each { |p| svc.vote!(p.id, @ana.id) }
    svc.end_vote!
    shown = House.new(@room.reload).public_state
    assert_equal House::GUEST, shown["out"].first["role"]
    assert_equal House::GHOST, shown["roles"][@ana.id.to_s]
  end

  # ── Phases ───────────────────────────────────────────────────────────────

  test "with two ghosts the night runs on until they agree on one victim" do
    @eli, @fer, @gus = %w[Eli Fer Gus].map { |n| @room.players.create!(nickname: n) }
    House.new(@room.reload).setup_game!
    deal!(ghosts: [ @ana, @beto ], medium: nil)
    night!
    (@room.players.to_a - [ @ana, @beto ]).each { |p| svc.hide!(p.id, "attic") }
    svc.ghost_pick!(@ana.id, @caro.id)
    svc.ghost_pick!(@beto.id, @dani.id)
    assert_not svc.night_done?

    svc.ghost_pick!(@beto.id, @caro.id)
    assert svc.night_done?
  end

  test "the host can skip only the discussion" do
    deal!
    night!
    assert_not svc.skip!
    svc.start_discussion!
    assert svc.skip!
    assert svc.skipped?("discussion")

    vote_phase! # a new phase clears the skip
    assert_not svc.skipped?("discussion")
  end

  test "the discussion lasts the room's setting, and every screen gets the seconds left" do
    deal!
    svc.start_discussion!
    assert_in_delta 60, House.new(@room.reload).public_state["seconds_left"], 1
  end

  test "the loop's bookkeeping never goes to a screen" do
    @room.atomic_set("game_state.loop_id" => "abc", "game_state.loop_beat" => 1.0)
    shown = House.new(@room.reload).player_state(@caro.id)
    assert_empty shown.keys & House::INTERNAL_KEYS
  end
end
