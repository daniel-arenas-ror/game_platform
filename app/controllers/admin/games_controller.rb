module Admin
  # The public catalog: which games it shows (`listed`) and their order (`position`), all games in one
  # form. A game without a position comes after the numbered ones, most rooms first (Game.catalog).
  # db:seed only sets these on a new game, so what is saved here stays.
  class GamesController < BaseController
    MAX_POSITION = 999

    def show
      @games = Game.in_catalog_order(Game.all.to_a)
    end

    # { games: { "<id>" => { position: "2", listed: "1" } } }. A blank position clears it.
    def update
      changes = params.fetch(:games, {})
      Game.where(:id.in => changes.keys).each do |game|
        attrs    = changes[game.id.to_s]
        position = attrs[:position].to_s.strip
        game.update!(position: position.empty? ? nil : position.to_i.clamp(1, MAX_POSITION),
                     listed:   attrs[:listed] == "1")
      end
      redirect_to admin_games_path, notice: "Games saved."
    end
  end
end
