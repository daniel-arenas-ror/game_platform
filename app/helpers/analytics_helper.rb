# Google Analytics (gtag.js). Production only, so local and test visits don't count.
# The measurement ID comes from the GA_MEASUREMENT_ID env var; without it nothing is loaded.
# Admin pages use their own layout and never load it.
#
# Custom events (the funnel). Inside a room each has Room#analytics_params; select_game comes before
# the room exists, so it only has the game and the language:
#   select_game   — a "Start game" button (controllers/analytics_controller.js)
#   room_created  — queued by the server with #track_analytics, sent on the next page (below)
#   players_joined — same way, on the player's phone after they join (with player_count)
#   game_started, play_again, game_finished — Room#broadcast_analytics, sent by the host's screen
module AnalyticsHelper
  def google_analytics_tag
    return unless analytics_enabled?

    safe_join([
      tag.script(async: true, src: "https://www.googletagmanager.com/gtag/js?id=#{ERB::Util.url_encode(ga_measurement_id)}"),
      javascript_tag(<<~JS)
        window.dataLayer = window.dataLayer || [];
        function gtag(){dataLayer.push(arguments);}
        gtag('js', new Date());
        gtag('config', #{ga_measurement_id.to_json});
      JS
    ], "\n")
  end

  # Microsoft Clarity (session recordings and heatmaps). Production only, like Google Analytics.
  # The project ID comes from the CLARITY_PROJECT_ID env var, else clarity_project_id in the credentials.
  # Room screens are masked (layouts/application: data-clarity-mask), so nicknames, guesses and
  # words never reach the recordings.
  def clarity_tag
    return unless clarity_enabled?

    javascript_tag(<<~JS)
      (function(c,l,a,r,i,t,y){
        c[a]=c[a]||function(){(c[a].q=c[a].q||[]).push(arguments)};
        t=l.createElement(r);t.async=1;t.src="https://www.clarity.ms/tag/"+i;
        y=l.getElementsByTagName(r)[0];y.parentNode.insertBefore(t,y);
      })(window, document, "clarity", "script", #{clarity_project_id.to_json});
      #{CLARITY_CONSENT_JS}
    JS
  end

  # Clarity keeps its cookies (one session across pages) for EU/UK/Swiss visitors only with their
  # consent. The consent message comes from AdSense (Google's CMP, IAB TCF): once it has loaded or the
  # visitor answered, pass on "store information on a device" (TCF purpose 1). Outside those regions
  # gdprApplies is false and Clarity works as before. Pages without the AdSense script have no CMP.
  CLARITY_CONSENT_JS = <<~JS.freeze
    (function() {
      var tries = 0;
      function listen() {
        if (typeof window.__tcfapi !== "function") { if (++tries < 40) setTimeout(listen, 500); return; }
        window.__tcfapi("addEventListener", 2, function(data, ok) {
          if (!ok || !data || (data.eventStatus !== "tcloaded" && data.eventStatus !== "useractioncomplete")) return;
          var granted = !data.gdprApplies || !!(data.purpose && data.purpose.consents && data.purpose.consents[1]);
          var value = granted ? "granted" : "denied";
          window.clarity("consentv2", { ad_Storage: value, analytics_Storage: value });
        });
      }
      listen();
    })();
  JS

  # Events the server queued for this page (ApplicationController#track_analytics). In the body,
  # not the head: Turbo runs a body's inline scripts on every visit.
  def queued_analytics_events_tag
    events = Array(flash[:analytics_events])
    return if events.empty? || !analytics_enabled?

    javascript_tag(events.map { |e| "gtag('event', #{e["name"].to_json}, #{e["params"].to_json});" }.join("\n"))
  end

  # `form:` options for a button_to that starts a room: sends select_game when it's pressed.
  # The game-over suggestions ("Maybe you'd like to play these too"): the form switches the room and
  # stops this screen following the phones (open-settings), and sends `suggested_game` with the room's
  # usual parameters, the suggested game as `game` and the one just played as `from_game`.
  def suggested_game_analytics(game, room)
    extra = room.analytics_params.slice(:room_code, :player_count).merge(from_game: room.game.slug)
    { data: { controller: "open-settings analytics",
              action: "submit->open-settings#stopListening submit->analytics#track",
              analytics_event_param: "suggested_game", analytics_game_param: game.slug,
              analytics_language_param: room.locale, analytics_extra_param: extra.to_json } }
  end

  def select_game_analytics(game)
    { data: { controller: "analytics", action: "submit->analytics#track",
              analytics_event_param: "select_game", analytics_game_param: game.slug,
              analytics_language_param: I18n.locale } }
  end

  private

  def analytics_enabled?
    Rails.env.production? && ga_measurement_id.present?
  end

  def clarity_enabled?
    Rails.env.production? && clarity_project_id.present?
  end

  def clarity_project_id
    ENV["CLARITY_PROJECT_ID"].presence || Rails.application.credentials.clarity_project_id
  end

  def ga_measurement_id
    ENV["GA_MEASUREMENT_ID"].presence || Rails.application.credentials.ga_measurement_id
  end
end
