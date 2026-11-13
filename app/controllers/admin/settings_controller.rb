module Admin
  # Site-wide switches (SiteSetting), shown on the Games page. For now, Christmas mode.
  class SettingsController < BaseController
    def update
      SiteSetting.current.update!(christmas: params[:christmas] == "1")
      redirect_to admin_games_path, notice: "Christmas mode is #{SiteSetting.christmas? ? 'on' : 'off'}."
    end
  end
end
