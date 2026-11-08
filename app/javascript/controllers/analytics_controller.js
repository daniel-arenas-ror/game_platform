import { Controller } from "@hotwired/stimulus"
import { track } from "controllers/shared/analytics"

// Sends a Google Analytics event from the page, e.g. on a "Start game" form:
//   data-action="submit->analytics#track"
//   data-analytics-event-param="select_game" data-analytics-game-param="mind-match"
//   data-analytics-language-param="es"
// data-analytics-extra-param='{"room_code": "AB12"}' adds more parameters (a JSON object).
export default class extends Controller {
  track({ params: { event, game, language, extra } }) {
    track(event, { game, game_name: game, game_language: language, ...(extra || {}) })
  }
}
