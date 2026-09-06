module ApplicationHelper
  # Renders a tiny SVG thumbnail of a BattleCity::MapPreset.
  # Used in the map picker on the room edit/lobby page.
  def battle_city_map_preview(preset, size: 60)
    cs = size.to_f / [preset.cols, preset.rows].max

    wall_color = { "brick" => "#c0392b", "steel" => "#7f8c8d",
                   "trees" => "#1e8449", "water" => "#2471a3" }

    rects = preset.cells.map do |cell|
      c = wall_color[cell["type"]] || "#888"
      x = (cell["x"] * cs).round(2)
      y = (cell["y"] * cs).round(2)
      w = [cs.ceil, 1].max
      %(<rect x="#{x}" y="#{y}" width="#{w}" height="#{w}" fill="#{c}"/>)
    end.join

    bx = (preset.base_x * cs).round(2)
    by = (preset.base_y * cs).round(2)
    bw = [cs.ceil, 1].max
    base = %(<rect x="#{bx}" y="#{by}" width="#{bw}" height="#{bw}" fill="#f39c12"/>)

    svg = %(<svg xmlns="http://www.w3.org/2000/svg" width="#{size}" height="#{size}" ) +
          %(style="background:#0d0d1a;border-radius:4px">#{rects}#{base}</svg>)

    svg.html_safe
  end
end
