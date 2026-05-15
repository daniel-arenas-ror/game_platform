import { Controller } from "@hotwired/stimulus"
import consumer from "channels/consumer"

export default class extends Controller {
  static values = { roomCode: String, userId: String }

  connect() {
    this.subscribe()
  }

  disconnect() {
    if (this.channel) {
      this.channel.unsubscribe()
    }
  }

  subscribe() {
    this.channel = consumer.subscriptions.create({
      channel: "Games::FishermanChannel",
      room_code: this.roomCodeValue
    }, {
      connected: () => {
        console.log("Connected to game channel!")
      },
      received: (data) => {
        // Handle your logic (refresh_game_frame, next_round_started, etc.)
        if (data.action === "refresh_game_frame" || data.action === "next_round_started") {
          window.location.reload() // Or use Turbo.visit
        }
      }
    })
  }
}
