class HomeController < ApplicationController
  def index
    # Old "Change Game" links pointed here with ?room=CODE; the catalog now lives on /games.
    redirect_to games_path(room: params[:room]) if params[:room].present?
  end

  def sitemap
    expires_in 1.day, public: true
  end

  def robots
    expires_in 1.day, public: true
  end
end
