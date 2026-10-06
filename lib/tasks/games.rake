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

  desc "Build the 1200×630 share image of each game page (public/games/<code>/og.png). ONLY=code builds one. Needs ImageMagick + pngquant."
  task og_images: :environment do
    bold    = ENV.fetch("OG_FONT_BOLD", "/System/Library/Fonts/Supplemental/Arial Bold.ttf")
    regular = ENV.fetch("OG_FONT", "/System/Library/Fonts/Supplemental/Arial.ttf")

    run = lambda do |*cmd|
      _out, err, status = Open3.capture3(*cmd)
      abort "#{cmd.first} failed: #{err}" unless status.success?
    end

    Dir[Rails.root.join("db/seeds/games/*.yml")].sort.each do |file|
      code  = File.basename(file, ".yml")
      next if ENV["ONLY"].present? && ENV["ONLY"] != code

      game  = YAML.load_file(file)
      art   = Rails.public_path.join("games", code, "instructions.png")
      out   = Rails.public_path.join("games", code, "og.png")
      color = GamePagesHelper::ACCENTS.dig(code, :hex) || "#d8b4fe"
      next puts("skip #{code}: no instructions.png") unless File.exist?(art)

      Dir.mktmpdir do |dir|
        card = File.join(dir, "card.png")

        # The instruction image: 360×540, rounded corners, a soft shadow, tilted like on the page.
        run.call("magick", art.to_s, "-resize", "360x540^", "-gravity", "north", "-extent", "360x540",
                 "(", "+clone", "-alpha", "extract", "-fill", "black", "-colorize", "100",
                 "-fill", "white", "-draw", "roundrectangle 0,0 359,539 28,28", ")",
                 "-alpha", "off", "-compose", "CopyOpacity", "-composite",
                 "(", "+clone", "-background", "black", "-shadow", "60x18+0+12", ")",
                 "+swap", "-background", "none", "-compose", "over", "-layers", "merge", "+repage",
                 "-rotate", "3", card)

        run.call("magick", "-size", "1200x630", "xc:#0b1120",
                 "(", "-size", "1100x1100", "radial-gradient:#3b0764-#0b1120", ")",
                 "-geometry", "-420-520", "-compose", "over", "-composite",
                 card, "-geometry", "+760+28", "-composite",
                 "-font", bold, "-fill", "#c084fc", "-pointsize", "22", "-kerning", "3",
                 "-annotate", "+72+92", "GROUPARTY  ·  FREE PARTY GAME", "-kerning", "0",
                 # Name and tagline stacked, so the tagline sits under the name however it wraps.
                 "(", "(", "-size", "640x", "-background", "none", "-fill", "white", "-font", bold,
                 "-pointsize", "72", "-interline-spacing", "-6", "caption:#{game.fetch('name')}", ")",
                 "(", "-size", "640x28", "xc:none", ")",
                 "(", "-size", "620x", "-background", "none", "-fill", color, "-font", bold,
                 "-pointsize", "32", "caption:#{game.fetch('tagline')}", ")",
                 "-background", "none", "-append", ")",
                 "-geometry", "+70+120", "-composite",
                 "-font", regular, "-fill", "#94a3b8", "-pointsize", "26",
                 "-annotate", "+72+560", "Host on the TV  ·  Play from your phone",
                 out.to_s)
      end

      run.call("pngquant", "--quality=70-90", "--force", "--skip-if-larger", "--output", out.to_s, out.to_s)
      puts "#{code}: #{out.relative_path_from(Rails.root)} (#{File.size(out) / 1024} KB)"
    end
  end
end
