class Room
  include Mongoid::Document
  include Mongoid::Timestamps

  field :name, type: String
  field :code, type: String       # The unique room code for the QR
  field :status, type: String, default: 'lobby'     # 'lobby', 'playing', 'finished'
  
  belongs_to :game
  has_many :players, dependent: :destroy

  # Since you want "in-memory" feel, you can still use Mongo 
  # or store the temporary state in a Hash field
  field :game_state, type: Hash, default: {}
  field :answers_history, type: Array, default: []

  before_create :generate_code

  # Atomically $set nested fields, e.g. atomic_set("game_state.status" => "revealing"), then reload.
  # Mongoid's #set on a Hash field rewrites the *whole* game_state from this in-memory copy, which
  # silently drops writes made meanwhile by other connections (e.g. a player's submitted answer).
  def atomic_set(fields)
    self.class.collection.update_one({ _id: id }, { "$set" => fields })
    reload
  end

  private

  def generate_code
    loop do
      self.code = SecureRandom.alphanumeric(4).upcase
      break unless Room.where(code: self.code).exists?
    end
  end
end
