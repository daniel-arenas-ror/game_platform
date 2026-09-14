import { Controller } from "@hotwired/stimulus"
import consumer from "channels/consumer"

export default class extends Controller {
  static values  = { roomCode: String }
  static targets = [
    "canvas",
    "phaseWaiting", "phaseShowing", "phaseReveal", "phaseGameOver",
    "countdown", "roundCounter", "roundCounter2", "difficultyBadge",
    "correctCount", "playerResults", "finalLeaderboard", "playAgain"
  ]

  connect() {
    this.subscribe()
  }

  disconnect() {
    this.channel?.unsubscribe()
  }

  subscribe() {
    this.channel = consumer.subscriptions.create({
      channel:   "Games::CountBirdsChannel",
      room_code: this.roomCodeValue,
      player_id: ""
    }, {
      connected: () => {
        console.log("[CountBirds Host] connected — starting game loop")
        this.channel.perform("start_game_loop", {})
      },
      received: (data) => this.handleMessage(data)
    })
  }

  handleMessage(data) {
    console.log("[CountBirds Host] received", data.action, data)
  }
}
