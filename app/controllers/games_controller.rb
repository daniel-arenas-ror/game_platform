# The game catalog. Hosts pick a game here to create a room.
class GamesController < ApplicationController
  def index
    @games = Game.all
    # Set when the host clicks "Change Game": picking a game switches this room instead of creating a new one.
    @room = Room.where(code: params[:room].to_s.upcase).first if params[:room].present?
  end

  def show
    @game = Game.find_by!(slug: params[:slug])
    @related_games = related_games(@game)
  end

  private

  # Same-category games first, then the rest of the catalog, in catalog order.
  def related_games(game, count = 3)
    others = Game.where(:id.ne => game.id, :slug.nin => [ nil, "" ]).to_a
    others.partition { |g| g.category == game.category }.flatten.first(count)
  end
end
