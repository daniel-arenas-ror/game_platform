import { Controller } from "@hotwired/stimulus"
import consumer from "channels/consumer"

export default class extends Controller {
  static values  = { roomCode: String, gridSize: Number }
  static targets = [
    "phaseWaiting", "phaseWatching", "phaseInput", "phaseReveal", "phaseGameOver",
    "grid", "grid2", "revealGrid",
    "roundLabel", "roundLabel2", "roundLabel3",
    "countdown", "playerResults", "finalLeaderboard", "playAgain"
  ]

  connect() {
    this.timerHandle = null
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
      player_id: ""
    }, {
      connected: () => {
        console.log("[SequenceMemory Host] connected — starting game loop")
        this.channel.perform("start_game_loop", {})
      },
      received: (data) => this.handleMessage(data)
    })
  }

  handleMessage(data) {
    console.log("[SequenceMemory Host] received", data.action, data)
  }
}
