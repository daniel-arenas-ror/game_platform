class Room
  include Mongoid::Document
  include Mongoid::Timestamps

  field :code, type: String       # The unique room code for the QR
  field :status, type: String, default: 'lobby'     # 'lobby', 'playing', 'finished'
  field :game_type, type: String  # 'impostor'
  
  belongs_to :game

  # Since you want "in-memory" feel, you can still use Mongo 
  # or store the temporary state in a Hash field
  field :game_state, type: Hash, default: {}

  private

  def generate_code
    self.code = SecureRandom.alphanumeric(4).upcase
  end
end
