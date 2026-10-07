class Player
  include Mongoid::Document
  include Mongoid::Timestamps

  field :nickname, type: String
  field :role, type: String
  field :connected, type: Boolean, default: false
  field :connections, type: Integer, default: 0   # open ActionCable subscriptions (see ApplicationCable::Channel)
  
  belongs_to :room

  # Players are deleted when they leave, so the stats count them here, when they join.
  after_create { Event.record(:player_joined, room: room) }
end
