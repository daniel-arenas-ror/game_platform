# The numbers on the admin dashboard, counted from the Event log inside MongoDB. Days are UTC.
#
# A period is a rolling window ending now ("7 days" = the last 7×24 hours), compared with the
# window just before it. "Today" starts at midnight UTC and is compared with yesterday up to the
# same time, so early in the day it isn't measured against a whole day.
class AdminStats
  RANGES = { "today" => "Today", "7d" => "7 days", "30d" => "30 days", "all" => "All time" }.freeze
  DEFAULT_RANGE = "7d".freeze
  # Most bars on a chart: all time counts per day, then per week, then per month, keeping the last ones.
  MAX_BARS = 60
  STEPS = { "hour" => 1.hour, "day" => 1.day, "week" => 1.week, "month" => 1.month }.freeze

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

  # The charts' bar size for the period: hours today, days for 7 and 30 days, and for all time days,
  # weeks or months, whichever first fits everything recorded in MAX_BARS bars.
  def chart_unit
    @chart_unit ||=
      case range
      when "today" then "hour"
      when "7d", "30d" then "day"
      else %w[day week].find { |unit| truncate(first_event_at, unit) >= truncate(now, unit) - (MAX_BARS - 1) * STEPS[unit] } || "month"
      end
  end

  # One row per chart_unit for the period, oldest first, empty ones included; the last is the
  # current, partial one. "7 days" is the last 7 UTC days counting today.
  def chart
    @chart ||= begin
      unit  = chart_unit
      last  = truncate(now, unit)
      first =
        case range
        when "today" then now.beginning_of_day
        when "7d"    then last - 6.days
        when "30d"   then last - 29.days
        else [ truncate(first_event_at, unit), last - (MAX_BARS - 1) * STEPS[unit] ].max
        end
      bucket = { "$dateTrunc" => { "date" => "$created_at", "unit" => unit, "startOfWeek" => "monday" } }
      counts = aggregate(first, now, { "at" => bucket, "kind" => "$kind" })
               .to_h { |row| [ [ row["_id"]["at"].to_i, row["_id"]["kind"] ], row["count"] ] }

      starts = [ first ]
      starts << starts.last + STEPS[unit] while starts.last < last
      starts.map do |at|
        { at: at, rooms: counts.fetch([ at.to_i, "room_created" ], 0), games: counts.fetch([ at.to_i, "game_started" ], 0),
          players: counts.fetch([ at.to_i, "player_joined" ], 0) }
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

  # The oldest event of any kind (rooms are rebuilt from older data), or now when there are none.
  def first_event_at
    @first_event_at ||= Event.order_by(created_at: :asc).only(:created_at).first&.created_at&.utc || now
  end

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

  # Start of the hour, day, week (Monday) or month `time` is in, in UTC.
  def truncate(time, unit)
    case unit
    when "hour"  then time.beginning_of_hour
    when "day"   then time.beginning_of_day
    when "week"  then time.beginning_of_week(:monday)
    when "month" then time.beginning_of_month
    end
  end

  def average(sum, count) = count.to_i.zero? ? nil : (sum.to_f / count).round(1)
end
