# The game catalog. Hosts pick a game here to create a room.
class GamesController < ApplicationController
  def index
    @games = Game.all
    # Set when the host clicks "Change Game": picking a game switches this room instead of creating a new one.
    @room = Room.where(code: params[:room].to_s.upcase).first if params[:room].present?
  end

  def show
    @game = Game.find_by!(slug: params[:slug])
  end
end
