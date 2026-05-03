class ApplicationController < ActionController::Base
  # Only allow modern browsers supporting webp images, web push, badges, import maps, CSS nesting, and CSS :has.
  allow_browser versions: :modern
  helper_method :current_player

  # Changes to the importmap will invalidate the etag for HTML responses
  stale_when_importmap_changes

  def current_player
    p " session[:player_id] = #{session[:player_id]}"
    @current_player ||= Player.find(session[:player_id]) if session[:player_id]
  rescue Mongoid::Errors::DocumentNotFound
    session[:player_id] = nil
    nil
  end
end
