# Google Analytics (gtag.js). Production only, so local and test visits don't count.
# The measurement ID comes from the GA_MEASUREMENT_ID env var; without it nothing is loaded.
# Admin pages use their own layout and never load it.
module AnalyticsHelper
  def google_analytics_tag
    measurement_id = ENV["GA_MEASUREMENT_ID"].presence || Rails.application.credentials.ga_measurement_id
    return unless Rails.env.production? && measurement_id.present?

    safe_join([
      tag.script(async: true, src: "https://www.googletagmanager.com/gtag/js?id=#{ERB::Util.url_encode(measurement_id)}"),
      javascript_tag(<<~JS)
        window.dataLayer = window.dataLayer || [];
        function gtag(){dataLayer.push(arguments);}
        gtag('js', new Date());
        gtag('config', #{measurement_id.to_json});
      JS
    ], "\n")
  end
end
