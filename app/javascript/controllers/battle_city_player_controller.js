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
  static targets = ["score", "colorBadge", "statusText", "dpad", "countdownOverlay",
                    "gameOverOverlay", "gameOverTitle", "gameOverSub", "finalScore"]

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
      case "game_restarted": window.location.reload();       break
    }
  }

  applySnapshot(state) {
    this.myScore = state.scores?.[this.playerIdValue] ?? 0
    const tank   = state.tanks?.[this.playerIdValue]
    if (tank && this.hasColorBadgeTarget) {
      this.colorBadgeTarget.style.backgroundColor = COLOR_HEX[tank.color] ?? "#888"
    }
    this.updateScore(this.myScore)
    if (tank) this.updateAliveState(tank.alive)
  }

  applyDelta(delta) {
    const myScore = delta.scores?.[this.playerIdValue]
    if (myScore !== undefined) {
      this.myScore = myScore
      this.updateScore(myScore)
    }

    const myTank = delta.tanks?.[this.playerIdValue]
    if (myTank !== undefined) this.updateAliveState(myTank.alive)
  }

  // Dim the dpad and show "Respawning…" when tank is dead
  updateAliveState(alive) {
    if (!this.hasDpadTarget) return
    if (alive) {
      this.dpadTarget.style.opacity  = "1"
      this.dpadTarget.style.filter   = ""
      const badge = this.dpadTarget.querySelector("[data-respawn-label]")
      if (badge) badge.remove()
    } else {
      this.dpadTarget.style.opacity  = "0.35"
      this.dpadTarget.style.filter   = "grayscale(1)"
      if (!this.dpadTarget.querySelector("[data-respawn-label]")) {
        const label = document.createElement("p")
        label.setAttribute("data-respawn-label", "")
        label.textContent  = "Respawning…"
        label.style.cssText = "position:absolute;inset:0;display:flex;align-items:center;justify-content:center;font-size:14px;font-weight:700;color:#94a3b8;letter-spacing:.1em;pointer-events:none;"
        this.dpadTarget.style.position = "relative"
        this.dpadTarget.appendChild(label)
      }
    }
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
    const myScore  = data.scores?.[this.playerIdValue] ?? this.myScore ?? 0
    const isWinner = data.winner_id === this.playerIdValue ||
                     (data.reason !== "base_destroyed" &&
                      data.winner_id == null &&
                      Object.values(data.scores ?? {}).length > 0 &&
                      myScore === Math.max(...Object.values(data.scores ?? {})))

    const reasons = {
      base_destroyed:     "The base was destroyed",
      last_tank_standing: "Last tank standing",
      kills_limit:        "Kill limit reached"
    }

    if (this.hasGameOverTitleTarget) {
      this.gameOverTitleTarget.textContent  = isWinner ? "YOU WIN!" : "GAME OVER"
      this.gameOverTitleTarget.style.color  = isWinner ? "#f1c40f" : "#ffffff"
    }
    if (this.hasGameOverSubTarget)
      this.gameOverSubTarget.textContent = reasons[data.reason] ?? ""
    if (this.hasFinalScoreTarget)
      this.finalScoreTarget.textContent = myScore

    if (this.hasGameOverOverlayTarget)
      this.gameOverOverlayTarget.classList.remove("hidden")
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
