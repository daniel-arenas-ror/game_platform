require "test_helper"

class GamePagesHelperTest < ActionView::TestCase
  # A test can point the helper at another public folder.
  def public_root
    @public_root || super
  end

  test "instruction images are WebP in two widths, with a content version in the URL" do
    game = Game.new(code: "mind_match")
    html = game_image_tag(game, sizes: "300px", alt: "")

    assert_match %r{src="/games/mind_match/instructions-640\.webp\?v=\h{10}"}, html
    assert_match %r{/games/mind_match/instructions-400\.webp\?v=\h{10} 400w, /games/mind_match/instructions-640\.webp\?v=\h{10} 640w}, html
    assert_includes html, 'sizes="300px"'
    assert_includes html, 'loading="lazy"'
    assert_not_includes html, "fetchpriority"
  end

  test "cards get the copy cut to the top part" do
    html = game_image_tag(Game.new(code: "mind_match"), sizes: "300px", card: true)

    assert_match %r{src="/games/mind_match/instructions-card-640\.webp\?v=\h{10}"}, html
    assert_includes html, "instructions-card-400.webp"
    assert_includes html, 'height="384"'
  end

  test "images seen without scrolling load first" do
    html = game_image_tag(Game.new(code: "mind_match"), sizes: "300px", priority: true)

    assert_includes html, 'loading="eager"'
    assert_includes html, 'fetchpriority="high"'
  end

  test "a game without WebP copies falls back to its PNG" do
    Dir.mktmpdir do |dir|
      FileUtils.mkdir_p(File.join(dir, "games", "new_game"))
      File.write(File.join(dir, "games", "new_game", "instructions.png"), "png")
      @public_root = Pathname(dir)

      html = game_image_tag(Game.new(code: "new_game"), sizes: "300px")
      assert_match %r{src="/games/new_game/instructions\.png\?v=\h{10}"}, html
      assert_not_includes html, "srcset"
    end
  end

  test "every game image has its WebP copies" do
    Dir[Rails.public_path.join("games", "*", "instructions.png")].each do |png|
      GamePagesHelper::IMAGE_WIDTHS.product([ "", "card-" ]).each do |width, kind|
        webp = png.sub("instructions.png", "instructions-#{kind}#{width}.webp")
        assert File.exist?(webp), "missing #{webp.delete_prefix("#{Rails.root}/")} — run bin/rails games:webp"
      end
    end
  end
end
