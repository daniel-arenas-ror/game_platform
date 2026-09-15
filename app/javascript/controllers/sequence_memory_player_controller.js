import { Controller } from "@hotwired/stimulus"
import consumer from "channels/consumer"

export default class extends Controller {
  static values  = { roomCode: String, playerId: String, gridSize: Number }
  static targets = [
    "phaseWaiting", "phaseWatching", "phaseInput", "phaseReveal", "phaseGameOver",
    "grid", "countdown", "tapProgress", "submittedLabel",
    "watchRoundLabel", "roundPointsLabel", "roundPointsDesc",
    "score", "gameOverTitle", "finalScore"
  ]

  connect() {
    this.taps        = []
    this.seqLength   = 0
    this.submitted   = false
    this.timerHandle = null
    this.totalScore  = 0
    this.subscribe()
  }

  disconnect() {
    this.channel?.unsubscribe()
    clearInterval(this.timerHandle)
  }

  subscribe() {
    this.channel = consumer.subscriptions.create({
      channel:   "Games::SequenceMemoryChannel",
      room_code: this.roomCodeValue,
      player_id: this.playerIdValue
    }, {
      connected: () => console.log("[SequenceMemory Player] connected"),
      received:  (data) => this.handleMessage(data)
    })
  }

  handleMessage(data) {
    console.log("[SequenceMemory Player] received", data.action, data)
  }
}
