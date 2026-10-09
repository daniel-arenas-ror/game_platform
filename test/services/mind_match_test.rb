require "test_helper"

class MindMatchTest < ActiveSupport::TestCase
  setup do
    @game = Game.create!(name: "Mind Match", code: "mind_match", description: "Match words")
    @room = Room.create!(game: @game)
    @ana, @beto, @caro = %w[Ana Beto Caro].map { |n| @room.players.create!(nickname: n) }

    # The host's game loop keeps its own long-lived Room object, like the channel thread does.
    @host_svc = GameServices::MindMatch.new(@room)
    @host_svc.setup_game!
    @host_svc.pick_category!
    @room.atomic_set("game_state.status" => "collecting")
  end

  teardown do
    Player.where(room_id: @room.id).delete_all
    @room.delete
    @game.delete
  end

  def submit(player, word)
    # Each player's channel loads its own copy of the room.
    GameServices::MindMatch.new(Room.find(@room.id)).add_answer(player.id, word)
  end

  test "answers survive the host moving the round to revealing" do
    assert submit(@ana, "sand")
    assert submit(@beto, "Sand")

    @room.atomic_set("game_state.status" => "revealing")
    result = @host_svc.score_round!

    assert_equal({ @ana.id.to_s => "sand", @beto.id.to_s => "Sand" }, result[:answers])
    assert_equal 2, result[:round_scores][@ana.id.to_s]
    assert_equal 2, result[:round_scores][@beto.id.to_s]
    assert_equal 0, result[:round_scores][@caro.id.to_s]
  end

  test "a player can only answer once per round" do
    assert submit(@ana, "sand")
    assert_not submit(@ana, "shell")
    assert_equal "sand", @room.reload.game_state["answers"][@ana.id.to_s]
  end

  test "answers are rejected once the round stops collecting" do
    @room.atomic_set("game_state.status" => "revealing")
    assert_not submit(@ana, "late")
    assert_empty @room.reload.game_state["answers"]
  end

  test "a Spanish room gets Spanish categories" do
    @room.update!(locale: "es")
    category = GameServices::MindMatch.new(Room.find(@room.id)).pick_category!
    assert_includes GameServices::MindMatch::CATEGORIES["es"], category
  end

  test "both languages have the same number of categories, all different" do
    en, es = GameServices::MindMatch::CATEGORIES.values_at("en", "es")
    assert_equal en.size, es.size
    assert_equal es.uniq, es
  end

  test "Spanish answers match without accents and in singular or plural" do
    svc  = GameServices::MindMatch.new(Room.new(locale: "es"))
    same = ->(a, b) { assert_equal svc.send(:normalize_word, a), svc.send(:normalize_word, b), "#{a} = #{b}" }

    same.("Camión", "camion")
    same.("gatos", "gato")
    same.("flores", "flor")
    same.("clases", "clase")
    same.("luces", "luz")
    same.("Peces!", "pez")
    same.("café", "cafés")
    assert_not_equal svc.send(:normalize_word, "gato"), svc.send(:normalize_word, "pato")
  end

  test "English answers ignore accents too" do
    svc = GameServices::MindMatch.new(Room.new(locale: "en"))
    assert_equal svc.send(:normalize_word, "cafe"), svc.send(:normalize_word, "Café")
    assert_equal svc.send(:normalize_word, "cat"), svc.send(:normalize_word, "cats")
  end
end
