# One record per thing that happened, for the admin stats. Written once and never changed, so the
# numbers survive when players are removed or a room switches games. No nicknames or other
# personal data: only what happened, when, and in which room and game.
class Event
  include Mongoid::Document

  KINDS = %w[room_created game_started player_joined].freeze

  field :kind,       type: String
  field :created_at, type: Time, default: -> { Time.current }
  field :room_id,    type: BSON::ObjectId
  field :game_id,    type: BSON::ObjectId
  field :players,    type: Integer # game_started: players in the room when the game started
  field :again,      type: Boolean # game_started: "play again", not the first game after the lobby

  validates :kind, inclusion: { in: KINDS }

  index({ kind: 1, created_at: 1 })
  index({ room_id: 1, kind: 1 })

  # Stats must never break the game: a failed write is logged and the request carries on.
  def self.record(kind, room:, **fields)
    create!(kind: kind.to_s, room_id: room.id, game_id: room.game_id, **fields)
  rescue StandardError => e
    Rails.logger.error("Event.record(#{kind}) failed: #{e.class}: #{e.message}")
    nil
  end
end
