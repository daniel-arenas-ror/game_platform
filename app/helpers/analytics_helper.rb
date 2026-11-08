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

  def ga_measurement_id
    ENV["GA_MEASUREMENT_ID"].presence || Rails.application.credentials.ga_measurement_id
  end
end
