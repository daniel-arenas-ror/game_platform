class HomeController < ApplicationController
  # Games suggested for each setting on the home page, best fit first.
  USE_CASE_GAMES = {
    classroom: %w[how_want_be_billionare sequence_memory count_birds],
    work:      %w[mind_match fisherman submarine_combat],
    family:    %w[guess_the_color soup_of_numbers battle_city]
  }.freeze

  def index
    # Old "Change Game" links pointed here with ?room=CODE; the catalog now lives on /games.
    return redirect_to games_path(room: params[:room]) if params[:room].present?

    games = Game.where(:code.in => USE_CASE_GAMES.values.flatten).index_by(&:code)
    @use_case_games = USE_CASE_GAMES.transform_values { |codes| codes.filter_map { |code| games[code] } }
    @games_count = Game.count
  end

  def sitemap
    expires_in 1.day, public: true
  end

  def robots
    expires_in 1.day, public: true
  end
end
