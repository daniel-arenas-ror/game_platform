# The numbers on the admin dashboard, counted from the Event log inside MongoDB. Days are UTC.
#
# A period is a rolling window ending now ("7 days" = the last 7×24 hours), compared with the
# window just before it. "Today" starts at midnight UTC and is compared with yesterday up to the
# same time, so early in the day it isn't measured against a whole day.
class AdminStats
  RANGES = { "today" => "Today", "7d" => "7 days", "30d" => "30 days", "all" => "All time" }.freeze
  DEFAULT_RANGE = "7d".freeze
  CHART_DAYS = 30

  attr_reader :range, :now

  def initialize(range: DEFAULT_RANGE, now: Time.now.utc)
    @range = RANGES.key?(range.to_s) ? range.to_s : DEFAULT_RANGE
    @now   = now.utc
  end

  def label = RANGES[range]

  # Start of the period, nil for all time.
  def from
    case range
    when "today" then now.beginning_of_day
    when "7d"    then now - 7.days
    when "30d"   then now - 30.days
    end
  end

  # { rooms:, games:, players:, avg_players: } for the period.
  def totals = @totals ||= summary(from, now)

  # The same numbers for the window just before, nil for all time.
  def previous_totals
    return if range == "all"

    @previous_totals ||= range == "today" ? summary(from - 1.day, now - 1.day) : summary(from - (now - from), from)
  end

  def previous_label = range == "today" ? "yesterday" : "previous #{label}"

  # One row per day for the last CHART_DAYS days, oldest first; today is the last, partial day.
  def daily
    @daily ||= begin
      start  = now.beginning_of_day - (CHART_DAYS - 1).days
      counts = aggregate(start, now, { "day" => { "$dateTrunc" => { "date" => "$created_at", "unit" => "day" } }, "kind" => "$kind" })
               .to_h { |row| [ [ row["_id"]["day"].to_date, row["_id"]["kind"] ], row["count"] ] }

      (0...CHART_DAYS).map do |i|
        day = (start + i.days).to_date
        { day: day, rooms: counts.fetch([ day, "room_created" ], 0), games: counts.fetch([ day, "game_started" ], 0),
          players: counts.fetch([ day, "player_joined" ], 0) }
      end
    end
  end

  # Games of the period, most played first: { game:, name:, games:, rooms:, players:, avg_players:, share: }.
  # A game nobody started this period but had rooms created still shows, below the played ones.
  def popular_games
    @popular_games ||= begin
      rows   = aggregate(from, now, { "game" => "$game_id", "kind" => "$kind" })
      games  = Game.in(_id: rows.map { |row| row["_id"]["game"] }.compact.uniq).index_by(&:id)
      played = totals[:games]

      # Games deleted since (old test games, renamed codes) share one row.
      rows.group_by { |row| games[row["_id"]["game"]] }.map do |game, by_game|
        sum     = ->(kind, field) { by_game.select { |row| row["_id"]["kind"] == kind }.sum { |row| row[field].to_i } }
        started = sum.call("game_started", "count")
        players = sum.call("game_started", "players")
        {
          game: game, name: game&.name || "Deleted games",
          games: started, rooms: sum.call("room_created", "count"), players: players,
          avg_players: average(players, started), share: played.zero? ? 0 : (100.0 * started / played)
        }
      end.sort_by { |row| [ -row[:games], -row[:rooms], row[:name] ] }
    end
  end

  # When game starts and player joins began to be recorded (rooms are rebuilt from older data).
  def tracking_since = Event.where(kind: "game_started").order_by(created_at: :asc).only(:created_at).first&.created_at

  # Percent change from the previous window: nil when there's nothing to compare with.
  def change(key)
    before = previous_totals&.dig(key)
    return if before.nil? || totals[key].nil?
    return (totals[key].zero? ? nil : :new) if before.zero?

    ((totals[key] - before) * 100.0 / before).round
  end

  private

  def summary(from, to)
    kinds = aggregate(from, to, "$kind").index_by { |row| row["_id"] }
    games = kinds.dig("game_started", "count").to_i

    { rooms: kinds.dig("room_created", "count").to_i, games: games, players: kinds.dig("player_joined", "count").to_i,
      avg_players: average(kinds.dig("game_started", "players"), games) }
  end

  # Events in [from, to), grouped by `group`, with how many there were and the players they had.
  def aggregate(from, to, group)
    window = { "$lt" => to }
    window["$gte"] = from if from

    Event.collection.aggregate([
      { "$match" => { "created_at" => window } },
      { "$group" => { "_id" => group, "count" => { "$sum" => 1 }, "players" => { "$sum" => { "$ifNull" => [ "$players", 0 ] } } } }
    ]).to_a
  end

  def average(sum, count) = count.to_i.zero? ? nil : (sum.to_f / count).round(1)
end
