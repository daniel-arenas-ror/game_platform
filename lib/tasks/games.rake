require "open3"
require "tmpdir"

namespace :games do
  desc "Recount Game#rooms_count from the rooms in the database (catalog popularity). Safe to re-run."
  task count_rooms: :environment do
    counts = Room.collection.aggregate([ { "$group" => { "_id" => "$game_id", "count" => { "$sum" => 1 } } } ])
                 .to_h { |row| [ row["_id"], row["count"] ] }

    Game.each do |game|
      game.set(rooms_count: counts.fetch(game.id, 0))
      puts "#{game.code}: #{game.rooms_count} rooms"
    end
  end

  # The PNG stays the source (the share images are made from it); pages show these WebP copies,
  # about a third of the size, at 400 and 640 px wide: the whole image, and a "card" one cut to
  # its top part for the cards that only show that (catalog, related games).
  desc "Build the WebP copies of each instructions.png. ONLY=code builds one. Needs libvips."
  task webp: :environment do
    Dir[Rails.public_path.join("games", "*", "instructions.png")].sort.each do |png|
      dir  = File.dirname(png)
      code = File.basename(dir)
      next if ENV["ONLY"].present? && ENV["ONLY"] != code

      built = GamePagesHelper::IMAGE_WIDTHS.flat_map do |width|
        # thumbnail fits inside width × height: a huge height means "this width, keep the shape";
        # the card one is cut to CARD_RATIO of the width, keeping the top ("low").
        card_height = (width * GamePagesHelper::CARD_RATIO).round
        {
          "instructions-#{width}.webp"      => [ "--height", "100000" ],
          "instructions-card-#{width}.webp" => [ "--height", card_height.to_s, "--crop", "low" ]
        }.map do |name, args|
          out = File.join(dir, name)
          _out, err, status = Open3.capture3("vips", "thumbnail", png, "#{out}[Q=75,effort=6,strip]", width.to_s, *args)
          abort "vips failed for #{code}: #{err}" unless status.success?
          "#{name.delete_prefix('instructions-')} #{File.size(out) / 1024} KB"
        end
      end
      puts "#{code}: #{File.size(png) / 1024} KB png → #{built.join(', ')}"
    end
  end

  desc "Build the 1200×630 share image of each game page (public/games/<code>/og.png). ONLY=code builds one. Needs ImageMagick + pngquant."
  task og_images: :environment do
    Dir[Rails.root.join("db/seeds/games/*.yml")].sort.each do |file|
      code = File.basename(file, ".yml")
      next if ENV["ONLY"].present? && ENV["ONLY"] != code

      game = YAML.load_file(file)
      art  = Rails.public_path.join("games", code, "instructions.png")
      next puts("skip #{code}: no instructions.png") unless File.exist?(art)

      out = OgImage.build(art: art, out: Rails.public_path.join("games", code, "og.png"),
                          eyebrow: "GROUPARTY  ·  FREE PARTY GAME", title: game.fetch("name"), tagline: game.fetch("tagline"),
                          footer: "Host on the TV  ·  Play from your phone",
                          color: GamePagesHelper::ACCENTS.dig(code, :hex) || "#d8b4fe")
      puts "#{code}: #{out.relative_path_from(Rails.root)} (#{File.size(out) / 1024} KB)"
    end
  end

  desc "Build the Christmas page's share images (public/christmas/og.png and og-es.png) from santa-family.png."
  task christmas_og: :environment do
    art = Rails.public_path.join("christmas", "santa-family.png")
    {
      "og.png"    => [ "GROUPARTY  ·  CHRISTMAS", "Christmas party games for the whole group",
                       "Trivia, drawing and word games with Christmas packs", "One TV  ·  Everyone plays on their phone" ],
      "og-es.png" => [ "GROUPARTY  ·  NAVIDAD", "Juegos de Navidad para todo el grupo",
                       "Preguntas, dibujos y palabras con paquetes navideños", "Una TV  ·  Todos juegan desde el celular" ]
    }.each do |file, (eyebrow, title, tagline, footer)|
      out = OgImage.build(art: art, out: Rails.public_path.join("christmas", file), eyebrow: eyebrow, title: title,
                          tagline: tagline, footer: footer, color: "#86efac", title_size: 60)
      puts "#{out.relative_path_from(Rails.root)} (#{File.size(out) / 1024} KB)"
    end
  end
end

# A 1200×630 share card: eyebrow, title and tagline on the left, the art as a tilted card on the right.
module OgImage
  BOLD    = ENV.fetch("OG_FONT_BOLD", "/System/Library/Fonts/Supplemental/Arial Bold.ttf")
  REGULAR = ENV.fetch("OG_FONT", "/System/Library/Fonts/Supplemental/Arial.ttf")

  def self.build(art:, out:, eyebrow:, title:, tagline:, footer:, color:, title_size: 72)
    Dir.mktmpdir do |dir|
      card = File.join(dir, "card.png")

      # The art: 360×540, rounded corners, a soft shadow, tilted like on the page.
      run("magick", art.to_s, "-resize", "360x540^", "-gravity", "north", "-extent", "360x540",
          "(", "+clone", "-alpha", "extract", "-fill", "black", "-colorize", "100",
          "-fill", "white", "-draw", "roundrectangle 0,0 359,539 28,28", ")",
          "-alpha", "off", "-compose", "CopyOpacity", "-composite",
          "(", "+clone", "-background", "black", "-shadow", "60x18+0+12", ")",
          "+swap", "-background", "none", "-compose", "over", "-layers", "merge", "+repage",
          "-rotate", "3", card)

      run("magick", "-size", "1200x630", "xc:#0b1120",
          "(", "-size", "1100x1100", "radial-gradient:#3b0764-#0b1120", ")",
          "-geometry", "-420-520", "-compose", "over", "-composite",
          card, "-geometry", "+760+28", "-composite",
          "-font", BOLD, "-fill", "#c084fc", "-pointsize", "22", "-kerning", "3",
          "-annotate", "+72+92", eyebrow, "-kerning", "0",
          # Title and tagline stacked, so the tagline sits under the title however it wraps.
          "(", "(", "-size", "640x", "-background", "none", "-fill", "white", "-font", BOLD,
          "-pointsize", title_size.to_s, "-interline-spacing", "-6", "caption:#{title}", ")",
          "(", "-size", "640x28", "xc:none", ")",
          # Settings carry over: without resetting the title's tight spacing, the tagline's last
          # line loses the bottom of its g, y and p.
          "(", "-size", "620x", "-background", "none", "-fill", color, "-font", BOLD, "-interline-spacing", "0",
          "-pointsize", "32", "caption:#{tagline}", ")",
          "-background", "none", "-append", ")",
          "-geometry", "+70+120", "-composite",
          "-font", REGULAR, "-fill", "#94a3b8", "-pointsize", "26",
          "-annotate", "+72+560", footer,
          out.to_s)
    end

    run("pngquant", "--quality=70-90", "--force", "--skip-if-larger", "--output", out.to_s, out.to_s)
    out
  end

  def self.run(*cmd)
    _out, err, status = Open3.capture3(*cmd)
    abort "#{cmd.first} failed: #{err}" unless status.success?
  end
end
