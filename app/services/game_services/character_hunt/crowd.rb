# Builds one round's crowd: a target, a few lookalikes of it (decoys: one or two things different),
# and everyone else, placed where people may stand in the scene. Pure functions, no database.
#
# A character is { "x", "y" (its feet, fractions of the scene), "h" (height, fraction of the scene
# height), "flip", "traits" }. The list is sorted back to front (by y), the order the browser draws
# it in, so on a tap the character in front is the last one whose box holds the point.
module GameServices::CharacterHunt::Crowd
  CATALOG = YAML.load_file(Rails.root.join("config/character_hunt/characters.yml")).freeze
  SCENES  = YAML.load_file(Rails.root.join("config/character_hunt/scenes.yml")).freeze

  # trait => the catalog list its value indexes
  TRAITS = {
    "skin" => "skin", "hair" => "hair_styles", "hair_color" => "hair_colors",
    "top" => "colors", "pattern" => "patterns", "pattern_color" => "colors",
    "legs" => "legs", "legs_color" => "leg_colors",
    "hat" => "hats", "hat_color" => "colors", "glasses" => "glasses",
    "extra" => "extras", "extra_color" => "colors", "beard" => "beards"
  }.freeze

  # Each theme's values for every trait (indexes), from characters.yml's `themes:`.
  THEMES = CATALOG["themes"].to_h do |theme, pools|
    [ theme, TRAITS.to_h do |key, list|
      values = CATALOG.fetch(list)
      [ key, pools[list] ? pools[list].map { |v| values.index(v) || raise("#{theme}: no #{v} in #{list}") } : (0...values.size).to_a ]
    end ]
  end.freeze

  # Parts that hide others: a pumpkin head covers hair, glasses and face.
  HEAD_COVERS = %w[pumpkin].freeze
  # Parts drawn in their own colours (no colour trait).
  FIXED_COLOR_HATS   = %w[none pumpkin].freeze
  FIXED_COLOR_EXTRAS = %w[none broom candy_bucket].freeze

  # Chance of none (index 0) for the optional parts.
  NONE_CHANCE = { "pattern" => 0.45, "hat" => 0.45, "glasses" => 0.65, "extra" => 0.6, "beard" => 0.75 }.freeze

  # What a decoy may change. Everyone else differs from the target in at least FILLER_DISTANCE traits,
  # so only the decoys can be mistaken for it.
  DECOY_CHANGES   = %w[hat hat_color top pattern pattern_color glasses extra extra_color legs legs_color hair hair_color beard].freeze
  FILLER_DISTANCE = 4

  # A character's box, in units of its height: HALF_WIDTH each side of the feet, HEIGHT up (with a hat).
  HALF_WIDTH = 0.22
  HEIGHT     = 1.1

  # Most of a box another character may cover, and how much of the target or a decoy may be
  # covered by someone standing in front of it.
  MAX_OVERLAP       = 0.4
  PROTECTED_OVERLAP = 0.15
  ATTEMPTS          = 80

  module_function

  # { "scene" => { "id", "ratio", "characters" }, "target_index" }. Can place fewer than `count`
  # people when the scene is full; the target and decoys are always there.
  def build(scene_id, count:, decoys:, size: 1.0)
    scene  = SCENES.fetch(scene_id)
    theme  = scene.fetch("theme")
    target = random_traits(theme)
    looks  = decoys_of(target, decoys, theme)
    people = [ target, *looks ] + Array.new(count - 1 - looks.size) { filler_for(target, theme) }

    placed = []
    people.each_with_index do |traits, i|
      protect = i <= looks.size
      spot    = find_spot(scene, size, placed, protect)
      next unless spot

      placed << spot.merge("flip" => [ true, false ].sample, "traits" => traits, "protected" => protect, "target" => i.zero?)
    end

    characters = placed.sort_by { |c| c["y"] }
    { "scene" => { "id" => scene_id, "ratio" => scene["ratio"],
                   "characters" => characters.map { |c| c.except("protected", "target") } },
      "target_index" => characters.index { |c| c["target"] } }
  end

  # The character (index) a tap at x, y (fractions of the scene) lands on, or nil.
  def hit(scene, x, y)
    ratio = scene["ratio"].to_f
    scene["characters"].rindex { |c| contains?(box(c, ratio), x.to_f * ratio, y.to_f) }
  end

  # ── Traits ───────────────────────────────────────────────────────────────

  def random_traits(theme = "classic")
    traits = TRAITS.keys.to_h { |key| [ key, random_value(key, theme) ] }
    traits["pattern_color"] = other_value("pattern_color", traits["top"], theme)
    normalize(traits)
  end

  # Drops the traits nobody can see (a bald head's hair colour, a plain top's pattern colour, the
  # hair under a pumpkin…), so two characters that look the same have equal traits.
  def normalize(traits)
    traits = traits.dup
    name   = ->(key) { CATALOG[TRAITS[key]][traits[key].to_i] }
    traits.except!("hair", "hair_color", "glasses", "beard") if HEAD_COVERS.include?(name.("hat"))
    traits.delete("hair_color") if name.("hair") == "bald" && %w[mustache beard].exclude?(name.("beard"))
    traits.delete("pattern_color") if name.("pattern") == "plain"
    traits.delete("hat_color") if FIXED_COLOR_HATS.include?(name.("hat"))
    traits.delete("extra_color") if FIXED_COLOR_EXTRAS.include?(name.("extra"))
    traits
  end

  # How many traits two characters differ in.
  def distance(a, b)
    (a.keys | b.keys).count { |key| a[key] != b[key] }
  end

  # `count` different lookalikes, each with one thing changed (two when the change shows a new
  # part: a hat appears with its colour).
  def decoys_of(target, count, theme = "classic")
    decoys = []
    (count * 30).times do
      break if decoys.size == count

      key = (DECOY_CHANGES & target.keys).sample
      decoy = target.merge(key => other_value(key, target[key], theme))
      TRAITS.each_key { |k| decoy[k] ||= random_value(k, theme, none: false) }
      decoy["pattern_color"] = other_value("pattern_color", decoy["top"], theme) if decoy["pattern_color"] == decoy["top"]
      decoy = normalize(decoy)
      next if decoy == target || decoys.include?(decoy) || distance(decoy, target) > 2

      decoys << decoy
    end
    decoys
  end

  def filler_for(target, theme = "classic")
    loop do
      traits = random_traits(theme)
      return traits if distance(traits, target) >= FILLER_DISTANCE
    end
  end

  def random_value(key, theme = "classic", none: true)
    pool = THEMES.fetch(theme).fetch(key)
    return 0 if none && NONE_CHANCE.key?(key) && rand < NONE_CHANCE[key]

    NONE_CHANCE.key?(key) ? (pool - [ 0 ]).sample : pool.sample
  end

  # Any other value of `key` in the theme (for a pattern colour: any colour but the top's).
  def other_value(key, value, theme = "classic")
    (THEMES.fetch(theme).fetch(key) - [ value ]).sample
  end

  # ── Placement ────────────────────────────────────────────────────────────

  # Somewhere to stand: inside an area, not in a hole, not hiding too much of anyone (or of the
  # target and decoys, nothing much), and not hidden much itself if it's protected.
  def find_spot(scene, size, placed, protect)
    ratio = scene["ratio"].to_f
    ATTEMPTS.times do
      x, y = random_point(scene)
      h    = (height_at(scene, y) * size).round(4)
      spot = { "x" => x.round(4), "y" => y.round(4), "h" => h }
      mine = box(spot, ratio)
      next if mine[0].negative? || mine[2] > ratio

      return spot if placed.all? do |other|
        theirs = box(other, ratio)
        shared = overlap(mine, theirs)
        next true if shared.zero?

        front_protected = (other["protected"] && y >= other["y"]) || (protect && other["y"] >= y)
        limit = front_protected ? PROTECTED_OVERLAP : MAX_OVERLAP
        shared <= limit * [ area(mine), area(theirs) ].min
      end
    end
    nil
  end

  def random_point(scene)
    areas = scene["areas"]
    loop do
      x0, y0, x1, y1 = areas.max_by { |a| rand**(1.0 / ((a[2] - a[0]) * (a[3] - a[1]))) } # weighted by size
      x, y = rand(x0..x1), rand(y0..y1)
      return [ x, y ] unless scene["holes"].any? { |hx0, hy0, hx1, hy1| x.between?(hx0, hx1) && y.between?(hy0, hy1) }
    end
  end

  # Smaller further back: from heights[0] at the top of the areas to heights[1] at the bottom.
  def height_at(scene, y)
    top        = scene["areas"].map { |a| a[1] }.min
    near, far  = scene["heights"].values_at(1, 0)
    far + (near - far) * ((y - top) / (1.0 - top)).clamp(0, 1)
  end

  # [left, top, right, bottom], in scene heights (x times the ratio).
  def box(character, ratio)
    x = character["x"].to_f * ratio
    y = character["y"].to_f
    h = character["h"].to_f
    [ x - HALF_WIDTH * h, y - HEIGHT * h, x + HALF_WIDTH * h, y ]
  end

  def contains?(box, x, y)
    x.between?(box[0], box[2]) && y.between?(box[1], box[3])
  end

  def overlap(a, b)
    w = [ a[2], b[2] ].min - [ a[0], b[0] ].max
    h = [ a[3], b[3] ].min - [ a[1], b[1] ].max
    w.positive? && h.positive? ? w * h : 0
  end

  def area(box)
    (box[2] - box[0]) * (box[3] - box[1])
  end
end
