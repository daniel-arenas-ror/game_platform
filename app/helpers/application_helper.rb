module ApplicationHelper
  SITE_HEADER_CONTROLLERS = %w[home games join pages].freeze

  # The public site (home, games, join, info pages) gets the top navigation; rooms and games don't.
  def site_header?
    SITE_HEADER_CONTROLLERS.include?(controller_name)
  end

  # Renders a tiny SVG thumbnail of a BattleCity::MapPreset.
  # Used in the map picker on the room edit/lobby page.
  def battle_city_map_preview(preset, size: 60)
    cs = size.to_f / [preset.cols, preset.rows].max

    wall_color = { "brick" => "#c0392b", "steel" => "#7f8c8d",
                   "trees" => "#1e8449", "water" => "#2471a3",
                   "pine" => "#2ecc71", "reindeer" => "#b07040", "lights" => "#f1c40f" }
    background = preset.theme == "christmas" ? "#0b1730" : "#0d0d1a"

    rects = preset.cells_without_base.map do |cell|
      c = wall_color[cell["type"]] || "#888"
      x = (cell["x"] * cs).round(2)
      y = (cell["y"] * cs).round(2)
      w = [cs.ceil, 1].max
      %(<rect x="#{x}" y="#{y}" width="#{w}" height="#{w}" fill="#{c}"/>)
    end.join

    svg = %(<svg xmlns="http://www.w3.org/2000/svg" width="#{size}" height="#{size}" ) +
          %(style="background:#{background};border-radius:4px">#{rects}</svg>)

    svg.html_safe
  end
end
