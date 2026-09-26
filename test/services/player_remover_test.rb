require "test_helper"

class PlayerRemoverTest < ActiveSupport::TestCase
  include ActionCable::TestHelper

  setup do
    @game = Game.create!(name: "Mind Match", code: "mind_match", description: "x")
    @room = Room.create!(game: @game, status: "playing")
    @ana  = @room.players.create!(nickname: "Ana")
    @bob  = @room.players.create!(nickname: "Bob")
    @room.atomic_set("game_state.scores"  => { @ana.id.to_s => 3, @bob.id.to_s => 1 },
                     "game_state.answers" => { @ana.id.to_s => "cat" },
                     "game_state.round"   => 2)
  end

  teardown do
    Player.where(room_id: @room.id).delete_all
    [ @room, @game ].each(&:delete)
  end

  test "removes a player who is still disconnected" do
    @ana.update!(connections: 0)

    assert_broadcasts("game_#{@room.code}", 1) do
      assert_broadcasts("mind_match_room_#{@room.code}", 1) do
        assert PlayerRemover.remove_if_disconnected(@ana.id)
      end
    end

    assert_nil Player.where(id: @ana.id).first
    state = @room.reload.game_state
    assert_equal({ @bob.id.to_s => 1 }, state["scores"])
    assert_equal({}, state["answers"])
    assert_equal 2, state["round"]
  end

  test "keeps a player who reconnected during the grace period" do
    @ana.update!(connections: 1)

    assert_not PlayerRemover.remove_if_disconnected(@ana.id)
    assert Player.where(id: @ana.id).exists?
  end

  test "fisherman re-deals roles when the fisherman leaves" do
    game = Game.create!(name: "Fisherman", code: "fisherman", description: "x")
    question = Fisherman::Question.create!(text: "Q?", answerds: [ "a" ])
    @room.update!(game: game)
    carl = @room.players.create!(nickname: "Carl", role: "knower")
    @ana.update!(role: "fisherman")
    @bob.update!(role: "impostor")

    PlayerRemover.new(@ana).remove!

    assert_equal %w[fisherman impostor], [ @bob, carl ].map { |p| p.reload.role }.sort
  ensure
    [ game, question ].compact.each(&:delete)
  end
end
