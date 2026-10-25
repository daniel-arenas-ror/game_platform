import { Controller } from "@hotwired/stimulus"
import consumer from "channels/consumer"
import { celebrateWin } from "controllers/shared/celebration"
import { t } from "controllers/shared/i18n"
import { TankSounds } from "controllers/battle_city/sounds"

const COLOR_HEX = {
  yellow: "#f1c40f",
  green:  "#2ecc71",
  white:  "#ecf0f1",
  red:    "#e74c3c"
}

export default class extends Controller {
  static values  = { roomCode: String, playerId: String }
  static targets = ["score", "colorBadge", "statusText", "dpad", "countdownOverlay",
                    "gameOverOverlay", "gameOverTitle", "gameOverSub", "finalScore", "soundButton"]

  connect() {
    console.log("[BattleCity Player] controller connected", this.roomCodeValue, this.playerIdValue)
    this.currentDir = null
    this.firing     = false
    this.moveTimer  = null
    this.playing    = false
    this.alive      = false
    this.sounds     = new TankSounds()
    this.unlockSound = () => this.sounds.unlock()
    // Phones allow sound only after a touch; any tap on the screen turns it on.
    ;["pointerdown", "pointerup", "touchend"].forEach(e => this.element.addEventListener(e, this.unlockSound, true))
    this.showSoundState()
    this.subscribe()
    this.bindDpad()
  }

  disconnect() {
    this.channel?.unsubscribe()
    clearInterval(this.moveTimer)
    ;["pointerdown", "pointerup", "touchend"].forEach(e => this.element.removeEventListener(e, this.unlockSound, true))
    this.sounds.close()
  }

  // ── Sound ─────────────────────────────────────────────────────────────────

  toggleSound() {
    this.sounds.setMuted(!this.sounds.muted)
    this.showSoundState()
  }

  showSoundState() {
    if (!this.hasSoundButtonTarget) return
    this.soundButtonTarget.textContent = this.sounds.muted ? "🔇" : "🔊"
    this.soundButtonTarget.setAttribute("aria-pressed", String(!this.sounds.muted))
  }

  // My tank was hit: boom (one, even when we took each other out), and a short buzz on phones that can vibrate (unless sound is off).
  onDestroyed() {
    this.sounds.explode()
    if (!this.sounds.muted) navigator.vibrate?.([120, 60, 220])
  }

  // The engine idles while my tank stands still and revs while a direction is held.
  refreshEngine() {
    const engine = !this.playing || !this.alive ? "off" : (this.currentDir ? "drive" : "calm")
    this.sounds.setEngine(engine)
  }


  // ── ActionCable ───────────────────────────────────────────────────────────

  subscribe() {
    this.channel = consumer.subscriptions.create({
      channel:   "Games::BattleCityChannel",
      room_code: this.roomCodeValue,
      player_id: this.playerIdValue
    }, {
      connected: () => console.log("[BattleCity Player] channel connected"),
      rejected: () => window.location.reload(),   // removed after a long disconnect → server sends us to /join
      received:  (data) => this.handleMessage(data)
    })
  }

  handleMessage(data) {
    switch (data.action) {
      case "state_snapshot": this.applySnapshot(data.state); break
      case "state_delta":    this.applyDelta(data.delta);    break
      case "countdown":      this.showCountdown(data.count); break
      case "game_over":      this.playing = false; this.refreshEngine(); this.showGameOver(data); break
      case "game_restarted": window.location.reload();       break
      case "game_changed":   window.location.href = `/rooms/${this.roomCodeValue}`; break
    }
  }

  applySnapshot(state) {
    this.myScore = state.scores?.[this.playerIdValue] ?? 0
    const tank   = state.tanks?.[this.playerIdValue]
    if (tank) this.paintTankColor(tank.color)
    this.updateScore(this.myScore)
    if (tank) this.updateAliveState(tank.alive, this.isOut(tank))
    this.playing   = state.status === "playing"
    this.refreshEngine()
  }

  applyDelta(delta) {
    // Scores only go up by destroying a tank, so a higher score means I just got one.
    const myScore = delta.scores?.[this.playerIdValue]
    const scored  = myScore !== undefined && myScore > (this.myScore ?? 0)
    if (myScore !== undefined) {
      this.myScore = myScore
      this.updateScore(myScore)
    }

    const myTank    = delta.tanks?.[this.playerIdValue]
    const destroyed = myTank !== undefined && this.alive && !myTank.alive
    if (myTank !== undefined) this.updateAliveState(myTank.alive, this.isOut(myTank))

    if (destroyed) this.onDestroyed()
    else if (scored) this.sounds.explode()
    else if (delta.bricks_by?.includes(this.playerIdValue)) this.sounds.brick()
    // The shot sounds when the server fires it (pressing Fire while a bullet is still flying does nothing).
    if (delta.shots?.includes(this.playerIdValue)) this.sounds.fire()
  }

  // The whole phone takes my tank's colour, so I can tell at a glance which tank on the TV is mine.
  // Red is dark enough for white text; yellow, green and white need dark text.
  paintTankColor(color) {
    const hex = COLOR_HEX[color]
    if (!hex) return
    this.element.style.backgroundColor = hex
    this.element.style.color = color === "red" ? "#ffffff" : "#0f172a"
    if (this.hasColorBadgeTarget) this.colorBadgeTarget.style.backgroundColor = hex
  }

  // Base-only survival: a destroyed tank has no respawn time, it's out until the next game.
  isOut(tank) {
    return !tank.alive && tank.respawn_tick == null
  }

  // Dim the dpad and show "Respawning…" (or "You're out") when tank is dead
  updateAliveState(alive, out = false) {
    this.alive = alive
    this.refreshEngine()
    if (!this.hasDpadTarget) return
    if (alive) {
      this.dpadTarget.style.opacity  = "1"
      this.dpadTarget.style.filter   = ""
      const badge = this.dpadTarget.querySelector("[data-respawn-label]")
      if (badge) badge.remove()
    } else {
      this.dpadTarget.style.opacity  = "0.35"
      this.dpadTarget.style.filter   = "grayscale(1)"
      let label = this.dpadTarget.querySelector("[data-respawn-label]")
      if (!label) {
        label = document.createElement("p")
        label.setAttribute("data-respawn-label", "")
        label.style.cssText = "position:absolute;inset:0;display:flex;align-items:center;justify-content:center;font-size:14px;font-weight:900;color:inherit;letter-spacing:.1em;pointer-events:none;"
        this.dpadTarget.style.position = "relative"
        this.dpadTarget.appendChild(label)
      }
      label.textContent = out ? t("battle_city.out") : t("battle_city.respawning")
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
      this.statusTextTarget.textContent = t("battle_city.go")
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

    if (this.hasGameOverTitleTarget) {
      this.gameOverTitleTarget.textContent  = isWinner ? t("battle_city.you_win") : t("battle_city.game_over")
      this.gameOverTitleTarget.style.color  = isWinner ? "#f1c40f" : "#ffffff"
    }
    if (this.hasGameOverSubTarget)
      this.gameOverSubTarget.textContent = data.reason ? t(`battle_city.reasons.${data.reason}`) : ""
    if (this.hasFinalScoreTarget)
      this.finalScoreTarget.textContent = myScore

    if (this.hasGameOverOverlayTarget)
      this.gameOverOverlayTarget.classList.remove("hidden")
    if (isWinner) celebrateWin(this.hasGameOverTitleTarget ? this.gameOverTitleTarget : null)
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
    this.refreshEngine()
    this.channel?.perform("player_input", {
      direction: this.currentDir,
      firing:    this.firing
    })
  }
}
