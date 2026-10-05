class Game
  include Mongoid::Document
  include Mongoid::Timestamps

  field :name, type: String
  field :code, type: String
  field :description, type: String

  # Public game page (/games/:slug). Content lives in db/seeds/games/<code>.yml.
  field :slug, type: String
  field :tagline, type: String
  field :long_description, type: String
  field :min_players, type: Integer
  field :max_players, type: Integer
  field :duration_minutes, type: Integer
  field :age, type: Integer
  field :category, type: String
  field :how_to_play, type: Array, default: []
  field :tips, type: Array, default: []
  field :perfect_for, type: Array, default: []
  field :faq, type: Array, default: [] # [{ "q" => "...", "a" => "..." }]

  index({ slug: 1 }, { unique: true, sparse: true })

  # Slugs are in public, indexed URLs: once a game is live, never change its slug.
  before_validation { self.slug = name.to_s.parameterize.tr("_", "-") if slug.blank? }
  validates :slug, presence: true, format: { with: /\A[a-z0-9]+(?:-[a-z0-9]+)*\z/ }

  def to_param
    slug
  end
end
