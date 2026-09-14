import { Controller } from "@hotwired/stimulus"
import consumer from "channels/consumer"

export default class extends Controller {
  static values  = { roomCode: String, playerId: String }
  static targets = [
    "phaseWaiting", "phaseCounting", "phaseReveal", "phaseGameOver",
    "countdown", "countDisplay", "submittedLabel",
    "correctCount", "myAnswer", "roundPointsLabel",
    "score", "gameOverTitle", "finalScore"
  ]

  connect() {
    this.count       = 0
    this.submitted   = false
    this.timerHandle = null
    this.subscribe()
  }

  disconnect() {
    this.channel?.unsubscribe()
    clearInterval(this.timerHandle)
  }

  subscribe() {
    this.channel = consumer.subscriptions.create({
      channel:   "Games::CountBirdsChannel",
      room_code: this.roomCodeValue,
      player_id: this.playerIdValue
    }, {
      connected: () => console.log("[CountBirds Player] connected"),
      received:  (data) => this.handleMessage(data)
    })
  }

  handleMessage(data) {
    console.log("[CountBirds Player] received", data.action, data)
  }

  increment() {}
  decrement() {}
}
