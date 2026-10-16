module MonsterMash
  # One part (head, body or legs) of one monster, drawn by one player. Kept out of the room's
  # game_state: a game has up to 12 monsters × 3 drawings, and game_state is read on every move.
  # `game_id` is the game's id (each Play Again starts a new one), so old drawings are never mixed in.
  class Drawing
    include Mongoid::Document
    include Mongoid::Timestamps

    field :room_id,   type: BSON::ObjectId
    field :game_id,   type: String
    field :monster,   type: Integer # index in game_state["monsters"]
    field :part,      type: String  # head / body / legs
    field :player_id, type: String
    field :strokes,   type: Array, default: [] # [{ "id", "color", "size", "points" => [[x, y], …] }]
    field :removed,   type: Array, default: [] # stroke ids undone before they were saved
    field :cleared_upto, type: Integer, default: 0
    field :done,      type: Boolean, default: false

    index({ room_id: 1, game_id: 1, monster: 1, part: 1 }, { unique: true })
  end
end
