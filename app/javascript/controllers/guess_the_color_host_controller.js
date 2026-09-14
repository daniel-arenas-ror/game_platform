import { Controller } from "@hotwired/stimulus"
import consumer from "channels/consumer"

export default class extends Controller {
  static values  = { roomCode: String }
  static targets = [
    "phaseWaiting", "phaseShowing", "phasePicking", "phaseReveal", "phaseGameOver",
    "colorBlock", "showingTimer", "pickingTimer", "submittedList",
    "revealGrid", "roundScores", "finalLeaderboard", "roundCounter", "playAgain"
  ]

  connect() {
    console.log("[GuessTheColor Host] connected", this.roomCodeValue)
    this.subscribe()
  }

  disconnect() {
    this.channel?.unsubscribe()
  }

  subscribe() {
    this.channel = consumer.subscriptions.create({
      channel:   "Games::GuessTheColorChannel",
      room_code: this.roomCodeValue,
      player_id: ""
    }, {
      connected: () => console.log("[GuessTheColor Host] channel connected"),
      received:  (data) => this.handleMessage(data)
    })
  }

  handleMessage(data) {
    console.log("[GuessTheColor Host] received", data.action, data)
  }
}
