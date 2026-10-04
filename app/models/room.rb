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

  # Shown in the join page's "where's the code?" illustration, so it must never be a real room.
  EXAMPLE_CODE = "K7QX".freeze

  # ActionCable stream of each game's in-game channel (the lobby uses "game_<code>").
  GAME_STREAM_PREFIXES = {
    "fisherman"              => "fisherman_room_",
    "how_want_be_billionare" => "millionaire_room_",
    "battle_city"            => "battle_city_room_",
    "guess_the_color"        => "guess_the_color_room_",
    "count_birds"            => "count_birds_room_",
    "sequence_memory"        => "sequence_memory_room_",
    "submarine_combat"       => "submarine_combat_room_",
    "mind_match"             => "mind_match_room_",
    "soup_of_numbers"        => "soup_of_numbers_room_"
  }.freeze

  def game_stream_name
    "#{GAME_STREAM_PREFIXES[game.code] || "#{game.code}_room_"}#{code}"
  end

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
      self.code = random_code
      break unless code == EXAMPLE_CODE || Room.where(code: code).exists?
    end
  end

  def random_code
    SecureRandom.alphanumeric(4).upcase
  end
end
