import { Controller } from "@hotwired/stimulus"
import { track } from "controllers/shared/analytics"

// Sends a Google Analytics event from the page, e.g. on a "Start game" form:
//   data-action="submit->analytics#track"
//   data-analytics-event-param="select_game" data-analytics-game-param="mind-match"
//   data-analytics-language-param="es"
export default class extends Controller {
  track({ params: { event, game, language } }) {
    track(event, { game, game_name: game, game_language: language })
  }
}
