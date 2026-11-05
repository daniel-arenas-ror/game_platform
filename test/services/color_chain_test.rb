require "test_helper"

class ColorChainTest < ActiveSupport::TestCase
  Chain = GameServices::ColorChain

  setup do
    @game = Game.create!(name: "Color Chain", code: "color_chain", description: "Repeat")
    @room = Room.create!(game: @game, game_state: { "start_length" => "2", "total_rounds" => "5" })
    @ana, @beto = %w[Ana Beto].map { |n| @room.players.create!(nickname: n) }
    Chain.new(@room).setup_game!
  end

  teardown do
    # Only this test's records: tests run in parallel against one database.
    Player.where(room_id: @room.id).delete_all
    Event.where(room_id: @room.id).delete_all
    @room.delete
    @game.delete
  end

  # Each player's channel loads its own copy of the room.
  def svc = Chain.new(Room.find(@room.id))
  def state = @room.reload.game_state
  def wrong(color) = (Chain::COLORS - [ color ]).first

  def input!(round = 1)
    svc.start_round!(round)
    svc.start_input!
  end

  test "reads the settings and falls back on values it doesn't offer" do
    assert_equal [ 2, 5, 6 ], [ state["start_length"], state["total_rounds"], state["chain"].length ]
    assert_empty state["chain"] - Chain::COLORS

    @room.atomic_set("game_state.start_length" => "99", "game_state.total_rounds" => "1")
    Chain.new(@room).setup_game!
    assert_equal [ 3, 10 ], [ state["start_length"], state["total_rounds"] ]
  end

  test "each round is the same sequence plus one colour" do
    lengths = (1..5).map do |round|
      svc.start_round!(round)
      assert_equal state["chain"].first(round + 1), svc.sequence
      svc.sequence.length
    end
    assert_equal [ 2, 3, 4, 5, 6 ], lengths
  end

  test "points stop at the first mistake" do
    seq = %w[red blue green yellow]
    assert_equal 4, Chain.correct_colors(seq, seq)
    assert_equal 2, Chain.correct_colors(seq, %w[red blue red yellow])
    assert_equal 0, Chain.correct_colors(seq, %w[blue blue green yellow])
    assert_equal 2, Chain.correct_colors(seq, %w[red blue])
    assert_equal 0, Chain.correct_colors(seq, [])
    assert_equal 0, Chain.correct_colors(seq, nil)
  end

  test "a round scores partial points, adds them up, and nothing for no answer" do
    input!(4) # five colours
    seq = svc.sequence
    assert svc.answer!(@ana.id, seq)
    assert svc.answer!(@beto.id, seq.first(3) + [ wrong(seq[3]), seq[4] ])
    assert svc.score_round!

    assert_equal({ @ana.id.to_s => 50, @beto.id.to_s => 30 }, state["round_scores"])
    assert_equal "reveal", state["phase"]

    input!(4)
    assert svc.answer!(@ana.id, seq)
    assert svc.score_round!
    assert_equal({ @ana.id.to_s => 100, @beto.id.to_s => 30 }, state["scores"])
  end

  test "an answer counts once, only while the phones are open, and only with real colours" do
    svc.start_round!(1)
    assert_not svc.answer!(@ana.id, svc.sequence), "phones are closed while the TV plays"

    svc.start_input!
    assert_not svc.answer!(@ana.id, %w[purple]), "not a colour"
    assert_not svc.answer!(@ana.id, "red"), "not a list"
    assert svc.answer!(@ana.id, svc.sequence)
    assert_not svc.answer!(@ana.id, %w[red]), "second answer"
    assert_not svc.answer!(BSON::ObjectId.new, svc.sequence), "not in this game"

    svc.score_round!
    assert_not svc.answer!(@beto.id, svc.sequence), "too late"
    assert_not svc.score_round!, "scored twice"
  end

  test "an answer longer than the sequence is cut" do
    input!
    assert svc.answer!(@ana.id, svc.sequence + %w[red red red])
    assert_equal svc.sequence, state["answers"][@ana.id.to_s]
  end

  test "all_answered? also holds when the last waiting player is removed" do
    input!
    svc.answer!(@ana.id, svc.sequence)
    assert_not svc.all_answered?

    PlayerRemover.new(@beto).remove!
    assert svc.all_answered?
  end

  test "a player who joins during the game can answer and keeps their points on a repeat join" do
    late = @room.players.create!(nickname: "Caro")
    assert svc.join!(late.id)
    input!
    assert svc.answer!(late.id, svc.sequence)
    svc.score_round!

    assert_not svc.join!(late.id)
    assert_equal 20, state["scores"][late.id.to_s]
  end

  test "phones never see the colours before the reveal; the TV always does" do
    %w[watching input].each_with_index do |phase, i|
      i.zero? ? svc.start_round!(1) : svc.start_input!
      assert_equal phase, state["phase"]
      shown = svc.public_state
      assert_equal 2, shown["sequence_length"]
      assert_empty shown.keys & %w[sequence chain answers loop_id]
      assert_equal svc.sequence, svc.host_state["sequence"]
    end

    svc.answer!(@ana.id, svc.sequence)
    assert_equal [ @ana.id.to_s ], svc.public_state["answered"]
    svc.score_round!
    assert_equal svc.sequence, svc.public_state["sequence"]
    assert_nil svc.public_state["chain"]
  end

  test "time per sequence grows with its length, within limits" do
    assert_equal [ 7, 13, 30 ], [ 2, 5, 18 ].map { Chain.input_seconds(_1) }
    assert_in_delta 1.85, Chain.playback_seconds(1)
    assert_in_delta 5.25, Chain.playback_seconds(5)
  end
end
