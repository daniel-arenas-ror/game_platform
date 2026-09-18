import { Controller } from "@hotwired/stimulus"
import consumer from "channels/consumer"

export default class extends Controller {
  static values = { roomCode: String, gridSize: Number, subCount: Number }

  connect() {
    this.subscribe()
  }

  disconnect() {
    this.channel?.unsubscribe()
  }

  subscribe() {
    this.channel = consumer.subscriptions.create({
      channel:   "Games::SubmarineCombatChannel",
      room_code: this.roomCodeValue,
      player_id: ""
    }, {
      connected: () => {
        console.log("[SubmarineCombat Host] connected")
      },
      received: (data) => this.handleMessage(data)
    })
  }

  handleMessage(data) {
    console.log("[SubmarineCombat Host] received", data.action, data)
    switch (data.action) {
      case "state_snapshot":    /* Phase 2 */ break
      case "placement_confirmed": /* Phase 2 */ break
      case "start_round":       /* Phase 3 */ break
      case "shot_submitted":    /* Phase 3 */ break
      case "round_result":      /* Phase 3 */ break
      case "game_over":         /* Phase 3 */ break
      case "game_restarted":    window.location.reload(); break
      case "game_changed":      window.location.href = `/rooms/${this.roomCodeValue}`; break
    }
  }
}
