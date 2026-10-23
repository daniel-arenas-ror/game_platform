# Development-only playground for Character Hunt's scene and zoom (no room, no channel): open it on
# a phone to try pinch-zoom and tapping. The route only exists in development.
class Dev::CharacterHuntController < ActionController::Base
  Crowd = GameServices::CharacterHunt::Crowd

  def show
    @scene_id   = Crowd::SCENES.key?(params[:scene]) ? params[:scene] : Crowd::SCENES.keys.sample
    @difficulty = GameServices::CharacterHunt::DIFFICULTIES.key?(params[:difficulty]) ? params[:difficulty] : "normal"
    @crowd      = Crowd.build(@scene_id, **GameServices::CharacterHunt::DIFFICULTIES.fetch(@difficulty))
    @catalog    = Crowd::CATALOG
  end
end
