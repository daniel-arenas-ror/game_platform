module BattleCity
  class MapPreset
    include Mongoid::Document
    include Mongoid::Timestamps

    field :name,         type: String
    field :cols,         type: Integer, default: 26
    field :rows,         type: Integer, default: 26
    # Sparse cell list — only non-empty cells stored
    # Each entry: { "x" => Integer, "y" => Integer, "type" => "brick"|"steel"|"water"|"trees" }
    field :cells,        type: Array,   default: []
    field :base_x,       type: Integer
    field :base_y,       type: Integer
    # Ordered list of tank spawn positions: [{ "x" => Integer, "y" => Integer }, ...]
    field :tank_spawns,  type: Array,   default: []
  end
end
