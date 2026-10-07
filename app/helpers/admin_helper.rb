module AdminHelper
  # The metrics on the dashboard: label and the bar color of their daily chart.
  ADMIN_METRICS = {
    rooms:   { label: "Rooms created",  bar: "fill-purple-400" },
    games:   { label: "Games played",   bar: "fill-green-400" },
    players: { label: "Players joined", bar: "fill-amber-300" }
  }.freeze

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
