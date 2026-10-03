# Google AdSense. Ads only appear on an allowlist of calm pages: never on game screens or forms,
# where players tap quickly on their phones and could click an ad by accident.
module AdsHelper
  ADSENSE_CLIENT = "ca-pub-5304803612075721".freeze

  # Ad unit IDs (data-ad-slot) from AdSense → Ads → By ad unit → Display ads.
  # A placement whose ID is blank renders nothing in production.
  AD_SLOTS = {
    home:  nil,
    lobby: nil,
    page:  nil
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

  # Renders one responsive ad unit. In development a dashed box shows where the ad will go.
  def ad_slot(placement, css: "")
    return unless ads_allowed?

    render "shared/ad_slot", placement: placement, slot_id: AD_SLOTS[placement], extra_class: css
  end
end
