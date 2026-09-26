class HomeController < ApplicationController
  def index
    @games = Game.all
    # Set when the host clicks "Change Game": picking a game switches this room instead of creating a new one.
    @room = Room.where(code: params[:room].to_s.upcase).first if params[:room].present?
  end

  def sitemap
    expires_in 1.day, public: true
  end

  def robots
    expires_in 1.day, public: true
  end
end
