import { Controller } from "@hotwired/stimulus"
import { track } from "controllers/shared/analytics"

// Sends a Google Analytics event from the page, e.g. on a "Start game" form:
//   data-action="submit->analytics#track"
//   data-analytics-event-param="select_game" data-analytics-game-param="mind-match"
//   data-analytics-language-param="es"
// data-analytics-extra-param='{"room_code": "AB12"}' adds more parameters (a JSON object).
// Once per form per page: impatient taps while the next page loads each fire `submit` (and Turbo
// restarts the request), but only one room is made. Back restores a fresh copy of the page.
export default class extends Controller {
  track({ params: { event, game, language, extra } }) {
    if (this.sent) return
    this.sent = true
    track(event, { game, game_name: game, game_language: language, ...(extra || {}) })
  }
}
