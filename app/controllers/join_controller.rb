# Players type the room code shown on the host's screen.
class JoinController < ApplicationController
  def show
    return unless params.key?(:code)

    code = params[:code].to_s.gsub(/[^a-zA-Z0-9]/, "").upcase

    if code.present? && Room.where(code: code).exists?
      redirect_to join_room_path(code)
    else
      redirect_to find_room_path, alert: code.present? ? "No room found with code #{code}." : "Enter a room code."
    end
  end
end
