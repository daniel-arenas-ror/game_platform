class Game
  include Mongoid::Document
  include Mongoid::Timestamps

  field :name, type: String
  field :code, type: String
  field :description, type: String

  # Catalog order: games with a position come first (1, 2, 3…), then the rest, most rooms first.
  field :position, type: Integer
  field :rooms_count, type: Integer, default: 0 # +1 for every room created with this game
  # false while a game is being built: hidden from the public site in production, shown in development.
  field :listed, type: Boolean, default: true

  # Public game page (/games/:slug). Content lives in db/seeds/games/<code>.yml.
  field :slug, type: String
  field :tagline, type: String
  field :long_description, type: String
  field :min_players, type: Integer
  field :max_players, type: Integer
  field :players_note, type: String # why this player count works best
  field :duration_minutes, type: Integer
  field :age, type: Integer
  field :category, type: String
  field :how_to_play, type: Array, default: []
  field :tips, type: Array, default: []
  field :perfect_for, type: Array, default: [] # keys of PERFECT_FOR
  field :faq, type: Array, default: [] # [{ "q" => "...", "a" => "..." }]

  # Other languages of the text fields, from the YAML's `translations:` block:
  # { "es" => { "name" => "...", "how_to_play" => [...], ... } }. English lives in the fields themselves.
  field :translations, type: Hash, default: {}
  TRANSLATED_FIELDS = %w[name description tagline long_description players_note how_to_play tips faq].freeze

  # Each text field reads the current language, falling back to English when it isn't translated.
  TRANSLATED_FIELDS.each do |name|
    define_method(name) do
      translations.dig(I18n.locale.to_s, name).presence || super()
    end
  end

  # Settings a game page can recommend it for.
  PERFECT_FOR = %w[party family classroom work video_call].freeze

  index({ slug: 1 }, { unique: true, sparse: true })

  # Slugs are in public, indexed URLs: once a game is live, never change its slug.
  before_validation { self.slug = name.to_s.parameterize.tr("_", "-") if slug.blank? }
  validates :slug, presence: true, format: { with: /\A[a-z0-9]+(?:-[a-z0-9]+)*\z/ }

  def self.catalog
    visible.to_a.sort_by { |g| [ g.position ? 0 : 1, g.position.to_i, -g.rooms_count.to_i, g.name.to_s ] }
  end

  # The games the public site shows.
  def self.visible
    Rails.env.development? ? all : where(:listed.ne => false)
  end

  def to_param
    slug
  end
end
