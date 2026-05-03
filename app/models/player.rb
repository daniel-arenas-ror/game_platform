class Player
  include Mongoid::Document
  include Mongoid::Timestamps

  field :nickname, type: String
  field :role, type: String
  field :connected, type: Boolean, default: false
  
  belongs_to :room
end
