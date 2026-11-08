require "test_helper"

# The host's game-over screen suggests 3 other games that suit the room's player count.
class GameSuggestionsTest < ActionDispatch::IntegrationTest
  setup do
    tag = SecureRandom.hex(3)
    @current = Game.create!(name: "Current #{tag}", code: "guess_the_color", description: "x", slug: "current-#{tag}", position: 1)
    @fits    = 3.times.map { |i| Game.create!(name: "Fits#{i} #{tag}", code: "mind_match", description: "x", slug: "fits#{i}-#{tag}", position: i + 2, max_players: 8) }
    @too_few = Game.create!(name: "Big #{tag}", code: "mind_match", description: "x", slug: "big-#{tag}", position: 5, min_players: 6)
    @room    = Room.create!(game: @current, status: "playing")
    2.times { |i| @room.players.create!(nickname: "P#{i}") }
  end

  teardown do
    Player.where(room_id: @room.id).delete_all
    @room.delete
    [ @current, *@fits, @too_few ].each(&:delete)
  end

  test "three other games that suit the room, each switching the room to it" do
    get "/rooms/#{@room.code}/playing"
    assert_response :success

    suggested = css_select("form[action='/rooms/#{@room.code}/change_game'] input[name=game_id]").map { _1["value"] } - [ @current.id.to_s ]
    assert_equal 3, suggested.size
    assert_not_includes suggested, @too_few.id.to_s, "needs more players than the room has"
  end

  test "a suggestion sends suggested_game with the game just played and the room" do
    get "/rooms/#{@room.code}/playing"
    form = css_select("form[data-analytics-event-param=suggested_game]").first
    assert form, "the suggestion forms are tracked"
    assert_includes form["data-action"], "submit->analytics#track"
    assert_includes form["data-action"], "submit->open-settings#stopListening"
    extra = JSON.parse(form["data-analytics-extra-param"])
    assert_equal({ "room_code" => @room.code, "player_count" => 2, "from_game" => @current.slug }, extra)
  end
end
