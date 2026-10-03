# Google AdSense. Ads only appear on an allowlist of calm pages, never on game screens or forms
# where players tap quickly on their phones and could click an ad by accident. The one exception
# is the host's Game Over screen (see #game_over_ad).
module AdsHelper
  ADSENSE_CLIENT = "ca-pub-5304803612075721".freeze

  # Ad unit IDs (data-ad-slot) from AdSense → Ads → By ad unit → Display ads.
  # A placement whose ID is blank renders nothing in production.
  AD_SLOTS = {
    home:      nil,
    lobby:     nil,
    page:      nil,
    game_over: nil
  }.freeze

  # controller => actions that may show ads
  ADS_ALLOWED = {
    "home"  => %w[index],
    "rooms" => %w[show],
    "pages" => %w[about contact privacy]
  }.freeze

  def ads_allowed?
    ADS_ALLOWED.fetch(controller_name, []).include?(action_name)
  end

  def adsense_script_tag
    return unless ads_allowed? && Rails.env.production?

    tag.script(async: true, crossorigin: "anonymous",
               src: "https://pagead2.googlesyndication.com/pagead/js/adsbygoogle.js?client=#{ADSENSE_CLIENT}")
  end

  # The only ad on a game screen: on the host's Game Over overlay, under the Play Again and
  # Change Game buttons. Players' phones never get it.
  def game_over_ad
    return unless controller_name == "rooms" && action_name == "playing" && session[:player_id].blank?

    render "shared/ad_slot", placement: :game_over, slot_id: AD_SLOTS[:game_over],
                              extra_class: "mt-12 w-full max-w-3xl mx-auto", format: "horizontal"
  end

  # Renders one responsive ad unit. In development a dashed box shows where the ad will go.
  def ad_slot(placement, css: "")
    return unless ads_allowed?

    render "shared/ad_slot", placement: placement, slot_id: AD_SLOTS[placement], extra_class: css
  end
end
