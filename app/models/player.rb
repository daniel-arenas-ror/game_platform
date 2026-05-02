class Player
  include Mongoid::Document
  include Mongoid::Timestamps

  field :nickname, type: String
  belongs_to :room
end
