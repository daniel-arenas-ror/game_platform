class Room
  include Mongoid::Document
  include Mongoid::Timestamps

  field :code, type: String       # The unique room code for the QR
  field :status, type: String, default: 'lobby'     # 'lobby', 'playing', 'finished'
  # Language of every screen in the room (lobby, join page, game), whatever the player's own setting.
  field :locale, type: String, default: "en"
  
  belongs_to :game
  has_many :players, dependent: :destroy

  # Since you want "in-memory" feel, you can still use Mongo 
  # or store the temporary state in a Hash field
  field :game_state, type: Hash, default: {}
  field :answers_history, type: Array, default: []

  validates :locale, inclusion: { in: ->(_) { I18n.available_locales.map(&:to_s) } }

  before_create :generate_code
  # Atomic, so rooms created at the same time are all counted.
  after_create { Game.where(_id: game_id).inc(rooms_count: 1) }
  after_create { Event.record(:room_created, room: self) }

  # Google Analytics: the host's screen hears these on RoomChannel and sends them
  # (room_players_controller), so each room counts once, not once per phone.
  after_update :broadcast_analytics, if: -> { previous_changes.key?("status") }

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
    "soup_of_numbers"        => "soup_of_numbers_room_",
    "matching_pairs"         => "matching_pairs_room_",
    "doodle_dash"            => "doodle_dash_room_",
    "haunted_house"          => "haunted_house_room_",
    "monster_mash"           => "monster_mash_room_"
  }.freeze

  def enough_players?
    players.count >= game.min_players_to_start
  end

  def broadcast_analytics
    event =
      case status
      when "playing"  then previous_changes["status"].first == "lobby" ? "game_started" : "play_again"
      when "finished" then "game_finished"
      end
    return unless event

    ActionCable.server.broadcast(RoomChannel.stream_for_room(code), {
      action: "analytics", event: event, params: { game_name: game.slug, player_count: players.count }
    })
  rescue StandardError => e # analytics must never break a game
    Rails.logger.error("Room#broadcast_analytics failed: #{e.class}: #{e.message}")
  end

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
