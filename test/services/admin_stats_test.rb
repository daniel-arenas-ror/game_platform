require "test_helper"

class AdminStatsTest < ActiveSupport::TestCase
  # Tests run in parallel on one database, so each test's events live in its own made-up stretch of
  # time far in the past, where nothing else writes, and the stats are asked "as of" then.
  setup do
    @now   = Time.utc(1000, 1, 1, 15) + SecureRandom.random_number(1_000_000) * 100.days
    @draw  = Game.create!(name: "Draw #{SecureRandom.hex(3)}", code: "doodle_dash", description: "x")
    @birds = Game.create!(name: "Birds #{SecureRandom.hex(3)}", code: "count_birds", description: "x")
    @rooms = []
  end

  teardown do
    Event.where(:created_at.gte => @now - 50.days, :created_at.lt => @now + 50.days).delete_all
    @draw.delete
    @birds.delete
  end

  def event(kind, at, game: @draw, players: nil)
    Event.create!(kind: kind, created_at: at, room_id: BSON::ObjectId.new, game_id: game.id, players: players)
  end

  def stats(range, now: @now) = AdminStats.new(range: range, now: now)

  test "counts the period's rooms, games, players and players per game" do
    event :room_created, @now - 1.hour
    event :room_created, @now - 3.days, game: @birds
    event :game_started, @now - 2.hours, players: 4
    event :game_started, @now - 2.days,  players: 2
    3.times { event :player_joined, @now - 5.hours }
    event :room_created, @now - 8.days # before the 7 days
    event :room_created, @now + 1.hour # after "now"

    assert_equal({ rooms: 2, games: 2, players: 3, avg_players: 3.0 }, stats("7d").totals)
    assert_equal({ rooms: 1, games: 1, players: 3, avg_players: 4.0 }, stats("today").totals)
    # All time has no start (its total includes other tests' events, so only its window is checked).
    assert_nil stats("all").from
  end

  test "today is compared with yesterday up to the same time" do
    event :room_created, @now - 1.hour
    event :room_created, @now - 1.day - 1.hour # yesterday, before this time
    event :room_created, @now - 1.day + 1.hour # yesterday, after this time: not counted

    assert_equal 1, stats("today").previous_totals[:rooms]
    assert_equal 0, stats("today").change(:rooms)
  end

  test "change against the previous window" do
    3.times { event :game_started, @now - 1.day, players: 2 }
    2.times { event :game_started, @now - 10.days, players: 2 }
    event :room_created, @now - 1.day

    assert_equal 50, stats("7d").change(:games)
    assert_equal :new, stats("7d").change(:rooms)
    assert_nil stats("7d").change(:players) # 0 and 0
    assert_nil stats("all").change(:games)
  end

  test "one row per UTC day for the chart, with empty days" do
    event :room_created, @now.beginning_of_day + 1.minute
    event :room_created, @now.beginning_of_day - 1.minute
    event :player_joined, @now - 29.days

    days = stats("7d").daily
    assert_equal AdminStats::CHART_DAYS, days.size
    assert_equal @now.to_date, days.last[:day]
    assert_equal [ 1, 1 ], days.last(2).map { _1[:rooms] }.reverse
    assert_equal 1, days.first[:players]
    assert_equal 0, days[10][:rooms]
  end

  test "the most played game comes first, with its share of the games" do
    3.times { event :game_started, @now - 1.day, game: @birds, players: 3 }
    event :game_started, @now - 1.day, players: 6
    2.times { event :room_created, @now - 1.day }
    event :room_created, @now - 1.day, game: @birds

    birds, draw = stats("7d").popular_games
    assert_equal [ @birds.name, 3, 1, 9, 3.0, 75.0 ], birds.values_at(:name, :games, :rooms, :players, :avg_players, :share)
    assert_equal [ @draw.name, 1, 2, 6.0, 25.0 ], draw.values_at(:name, :games, :rooms, :avg_players, :share)
  end

  test "deleted games share one row" do
    2.times do
      gone = Game.create!(name: "Gone", code: "count_birds", description: "x")
      event :room_created, @now - 1.day, game: gone
      gone.delete
    end

    deleted = stats("7d").popular_games.find { _1[:game].nil? }
    assert_equal [ "Deleted games", 2 ], deleted.values_at(:name, :rooms)
  end

  test "an unknown range falls back to 7 days" do
    assert_equal "7d", AdminStats.new(range: "forever").range
  end
end
