import { Controller } from "@hotwired/stimulus"
import consumer from "channels/consumer"

// "Change settings" on the host's Game Over screen. The room's game_changed message sends every
// screen to the lobby, and it reaches this one before the settings page does, so the host stops
// listening first. Any later page that subscribes opens the connection again.
export default class extends Controller {
  stopListening() {
    consumer.disconnect()
  }
}
