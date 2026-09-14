import { Controller } from "@hotwired/stimulus"
import consumer from "channels/consumer"

export default class extends Controller {
  static values  = { roomCode: String, playerId: String }
  static targets = [
    "phaseWaiting", "phaseWatch", "phasePicking", "phaseSubmitted", "phaseReveal", "phaseGameOver",
    "colorPreview", "sliderR", "sliderG", "sliderB", "valueR", "valueG", "valueB",
    "pickingTimer", "submitBtn", "submittedPreview",
    "targetPreview", "myPickPreview", "roundPointsLabel",
    "score", "gameOverTitle", "finalScore"
  ]

  connect() {
    console.log("[GuessTheColor Player] connected", this.roomCodeValue, this.playerIdValue)
    this.subscribe()
  }

  disconnect() {
    this.channel?.unsubscribe()
  }

  subscribe() {
    this.channel = consumer.subscriptions.create({
      channel:   "Games::GuessTheColorChannel",
      room_code: this.roomCodeValue,
      player_id: this.playerIdValue
    }, {
      connected: () => console.log("[GuessTheColor Player] channel connected"),
      received:  (data) => this.handleMessage(data)
    })
  }

  handleMessage(data) {
    console.log("[GuessTheColor Player] received", data.action, data)
  }
}
