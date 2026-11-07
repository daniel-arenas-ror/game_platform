module BattleCity
  class MapPreset
    include Mongoid::Document
    include Mongoid::Timestamps

    field :name,         type: String
    field :cols,         type: Integer, default: 26
    field :rows,         type: Integer, default: 26
    # Sparse cell list — only non-empty cells stored
    # Each entry: { "x" => Integer, "y" => Integer, "type" => "brick"|"steel"|"water"|"trees" }, and on
    # the Christmas maps "pine" (a decorated tree, like trees), "reindeer" (like steel) and "lights"
    # (a string of bulbs, like brick).
    field :cells,        type: Array,   default: []
    field :base_x,       type: Integer
    field :base_y,       type: Integer
    # Ordered list of tank spawn positions: [{ "x" => Integer, "y" => Integer }, ...]
    field :tank_spawns,  type: Array,   default: []
    # "christmas": night-blue ground with falling snow on the TV. Nil = the plain look.
    field :theme,        type: String

    # The game has no base for now (a later mode may bring it back), so the walls that guard it
    # are left out too: everything up to 3 cells either side of it, on its row and the one above.
    BASE_FORT_REACH = 3

    def cells_without_base
      cells.reject do |cell|
        (cell["x"] - base_x).abs <= BASE_FORT_REACH && cell["y"] >= base_y - 1 && cell["y"] <= base_y
      end
    end
  end
end
