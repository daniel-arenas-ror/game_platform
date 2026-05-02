class Room
  include Mongoid::Document
  include Mongoid::Timestamps

  field :code, type: String       # The unique room code for the QR
  field :status, type: String     # 'lobby', 'playing', 'finished'
  field :game_type, type: String  # 'impostor'
  
  # Since you want "in-memory" feel, you can still use Mongo 
  # or store the temporary state in a Hash field
  field :game_state, type: Hash, default: {} 
end
