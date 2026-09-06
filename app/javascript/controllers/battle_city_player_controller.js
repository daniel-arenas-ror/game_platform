import { Controller } from "@hotwired/stimulus"
import consumer from "channels/consumer"

const COLOR_HEX = {
  yellow: "#f1c40f",
  green:  "#2ecc71",
  white:  "#ecf0f1",
  red:    "#e74c3c"
}

export default class extends Controller {
  static values  = { roomCode: String, playerId: String }
  static targets = ["score", "colorBadge", "statusText", "dpad", "countdownOverlay"]

  connect() {
    console.log("[BattleCity Player] controller connected", this.roomCodeValue, this.playerIdValue)
    this.currentDir = null
    this.firing     = false
    this.moveTimer  = null
    this.subscribe()
    this.bindDpad()
  }

  disconnect() {
    this.channel?.unsubscribe()
    clearInterval(this.moveTimer)
  }

  // ── ActionCable ───────────────────────────────────────────────────────────

  subscribe() {
    this.channel = consumer.subscriptions.create({
      channel:   "Games::BattleCityChannel",
      room_code: this.roomCodeValue,
      player_id: this.playerIdValue
    }, {
      connected: () => console.log("[BattleCity Player] channel connected"),
      received:  (data) => this.handleMessage(data)
    })
  }

  handleMessage(data) {
    switch (data.action) {
      case "state_snapshot": this.applySnapshot(data.state); break
      case "state_delta":    this.applyDelta(data.delta);    break
      case "countdown":      this.showCountdown(data.count); break
      case "game_over":      this.showGameOver(data);        break
    }
  }

  applySnapshot(state) {
    const tank = state.tanks?.[this.playerIdValue]
    if (tank && this.hasColorBadgeTarget) {
      this.colorBadgeTarget.style.backgroundColor = COLOR_HEX[tank.color] ?? "#888"
    }
    this.updateScore(state.scores?.[this.playerIdValue] ?? 0)
  }

  applyDelta(delta) {
    const myScore = delta.scores?.[this.playerIdValue]
    if (myScore !== undefined) this.updateScore(myScore)
  }

  updateScore(score) {
    if (this.hasScoreTarget) this.scoreTarget.textContent = score
  }

  // ── Countdown ─────────────────────────────────────────────────────────────

  showCountdown(count) {
    if (!this.hasCountdownOverlayTarget || !this.hasStatusTextTarget) return

    if (count > 0) {
      this.countdownOverlayTarget.classList.remove("hidden")
      this.statusTextTarget.textContent = count
    } else {
      this.statusTextTarget.textContent = "GO!"
      setTimeout(() => this.countdownOverlayTarget.classList.add("hidden"), 700)
    }
  }

  showGameOver(data) {
    console.log("[BattleCity] game over", data)
  }

  // ── D-pad — Pointer Events (works on touch + mouse) ───────────────────────

  bindDpad() {
    // Attach listeners directly to each d-pad button using Pointer Events.
    // pointerdown/pointerup fire on both touch screens and mice.
    this.element.querySelectorAll("[data-direction]").forEach(btn => {
      btn.addEventListener("pointerdown", (e) => {
        e.preventDefault()
        console.log("[BattleCity Player] pointerdown", btn.dataset.direction)
        btn.setPointerCapture(e.pointerId)   // keep events on this element even if pointer drifts off
        const dir = btn.dataset.direction
        clearInterval(this.moveTimer)
        this.currentDir = dir
        this.sendInput()
        this.moveTimer = setInterval(() => this.sendInput(), 120)
      })

      btn.addEventListener("pointerup", (e) => {
        e.preventDefault()
        clearInterval(this.moveTimer)
        this.moveTimer  = null
        this.currentDir = null
        this.sendInput()
      })

      btn.addEventListener("pointercancel", (e) => {
        clearInterval(this.moveTimer)
        this.moveTimer  = null
        this.currentDir = null
        this.sendInput()
      })
    })

    // Fire button
    const fireBtn = this.element.querySelector("[data-fire]")
    if (fireBtn) {
      fireBtn.addEventListener("pointerdown", (e) => {
        e.preventDefault()
        fireBtn.setPointerCapture(e.pointerId)
        this.firing = true
        this.sendInput()
      })

      fireBtn.addEventListener("pointerup",     (e) => { this.firing = false; this.sendInput() })
      fireBtn.addEventListener("pointercancel",  (e) => { this.firing = false; this.sendInput() })
    }
  }

  sendInput() {
    this.channel?.perform("player_input", {
      direction: this.currentDir,
      firing:    this.firing
    })
  }
}
