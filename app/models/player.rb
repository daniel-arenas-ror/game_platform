class Player
  include Mongoid::Document
  include Mongoid::Timestamps

  field :nickname, type: String
  field :role, type: String
  belongs_to :room
end
