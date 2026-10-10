module AdminHelper
  # The metrics on the dashboard: label and the bar color of their daily chart.
  ADMIN_METRICS = {
    rooms:   { label: "Rooms created",  bar: "fill-purple-400" },
    games:   { label: "Games played",   bar: "fill-green-400" },
    players: { label: "Players joined", bar: "fill-amber-300" }
  }.freeze

  ROOM_STATUS_STYLES = {
    "lobby"    => "text-amber-200 bg-amber-500/10 border-amber-500/30",
    "playing"  => "text-green-200 bg-green-500/10 border-green-500/30",
    "finished" => "text-slate-300 bg-slate-500/10 border-slate-500/30"
  }.freeze

  # The pages in the admin menu: label, path helper and the controller that marks it current.
  def admin_menu
    [ [ "Dashboard", admin_root_path, "admin/dashboard" ], [ "Rooms", admin_rooms_path, "admin/rooms" ] ]
  end

  def admin_room_status(status)
    tag.span(status, class: "inline-block rounded-md border px-2 py-0.5 text-xs font-bold #{ROOM_STATUS_STYLES.fetch(status.to_s, ROOM_STATUS_STYLES["finished"])}")
  end

  # "Oct 10, 14:05 UTC" with "3 hours ago" on hover. Like the stats, admin times are in UTC.
  def admin_time(time)
    return "—" unless time

    tag.time(time.utc.strftime("%b %-d, %H:%M UTC"), datetime: time.utc.iso8601, title: "#{time_ago_in_words(time)} ago")
  end

  # "+12%", "−8%", "New" or nil: the change since the previous window, with its color.
  def admin_change_badge(change)
    return if change.nil?

    text, style =
      if change == :new then [ "New", "text-green-300 bg-green-500/10" ]
      elsif change.positive? then [ "+#{change}%", "text-green-300 bg-green-500/10" ]
      elsif change.negative? then [ "−#{change.abs}%", "text-red-300 bg-red-500/10" ]
      else [ "0%", "text-slate-300 bg-slate-500/10" ]
      end
    tag.span(text, class: "rounded-md px-1.5 py-0.5 text-xs font-bold tabular-nums #{style}")
  end

  # A server-drawn bar chart of one metric per day. Each bar has a hover tooltip; the exact numbers
  # are also in the table under the charts. Today's bar is lighter: the day isn't over yet.
  def admin_daily_chart(days, key)
    width, height, gap = 600.0, 96.0, 3.0
    max  = [ days.map { _1[key] }.max.to_i, 1 ].max
    step = width / days.size

    bars = days.each_with_index.map do |row, i|
      value = row[key]
      h     = value.zero? ? 1.5 : [ (value.to_f / max) * height, 3 ].max
      tag.rect(x: (i * step + gap / 2).round(2), y: (height - h).round(2), width: (step - gap).round(2), height: h.round(2), rx: 2,
               class: "#{value.zero? ? 'fill-slate-700' : ADMIN_METRICS.dig(key, :bar)}#{' opacity-60' if i == days.size - 1}") do
        tag.title("#{row[:day].strftime('%a %b %-d')}: #{value}")
      end
    end

    tag.svg(safe_join(bars), viewBox: "0 0 #{width.to_i} #{height.to_i}", preserveAspectRatio: "none",
                             class: "block h-24 w-full", role: "img",
                             aria: { label: "#{ADMIN_METRICS.dig(key, :label)} per day, highest #{max}" })
  end
end
