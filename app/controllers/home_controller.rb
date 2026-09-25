class HomeController < ApplicationController
  def index
    @games = Game.all
  end

  def sitemap
    expires_in 1.day, public: true
  end

  def robots
    expires_in 1.day, public: true
  end
end
