import { Controller } from "@hotwired/stimulus"
import consumer from "channels/consumer"
import { t, placeTitle } from "controllers/shared/i18n"
import { celebrateWin, isTopScore } from "controllers/shared/celebration"

export default class extends Controller {
  static values  = { roomCode: String, playerId: String }
  static targets = [
    "phaseWaiting", "phaseWatch", "phasePicking", "phaseSubmitted", "phaseReveal", "phaseGameOver",
    "colorPreview", "sliderHue", "sliderLight", "sliderSat",
    "pickingTimer", "submittedLabel", "submittedPreview",
    "targetPreview", "targetName", "myPickPreview", "matchLabel", "pickNote", "roundPointsLabel",
    "score", "gameOverTitle", "finalScore"
  ]

  connect() {
    this.timerHandle = null
    this.submitted   = false
    this.myPick      = null
    this.totalScore  = 0
    this.subscribe()
    this.resetSliders()
  }

  disconnect() {
    this.channel?.unsubscribe()
    clearInterval(this.timerHandle)
  }

  // ── ActionCable ───────────────────────────────────────────────────────────

  subscribe() {
    this.channel = consumer.subscriptions.create({
      channel:   "Games::GuessTheColorChannel",
      room_code: this.roomCodeValue,
      player_id: this.playerIdValue
    }, {
      connected: () => console.log("[GuessTheColor Player] channel connected"),
      rejected: () => window.location.reload(),   // removed after a long disconnect → server sends us to /join
      received:  (data) => this.handleMessage(data)
    })
  }

  handleMessage(data) {
    switch (data.action) {
      case "state_snapshot":  this.applySnapshot(data.state); break
      case "show_color":      this.onShowColor(data);         break
      case "start_picking":   this.onStartPicking(data);      break
      case "reveal":          this.onReveal(data);            break
      case "game_over":       this.onGameOver(data);          break
      case "game_restarted":  window.location.reload();       break
      case "game_changed":    window.location.href = `/rooms/${this.roomCodeValue}`; break
    }
  }

  // ── Phase handlers ────────────────────────────────────────────────────────

  applySnapshot(state) {
    if (!state) return
    this.totalScore = state.scores?.[this.playerIdValue] ?? 0
    this.updateScore(this.totalScore)

    switch (state.status) {
      case "showing_color": this.showPhase("phaseWatch");    break
      case "picking":       this.showPhase("phasePicking");  break
      case "revealing":     this.showPhase("phaseWatch");    break  // waiting for reveal broadcast
      case "game_over":     this.showPhase("phaseGameOver"); break
      default:              this.showPhase("phaseWaiting");
    }
  }

  onShowColor(data) {
    this.stopTimer()
    this.submitted = false
    this.myPick    = null
    this.resetSliders()
    this.showPhase("phaseWatch")
  }

  onStartPicking(data) {
    this.stopTimer()
    this.submitted = false

    // Re-enable sliders for the new round
    this.sliders().forEach(slider => { slider.disabled = false })
    if (this.hasSubmittedLabelTarget) this.submittedLabelTarget.classList.add("hidden")

    this.showPhase("phasePicking")
    this.startCountdown(data.duration)
  }

  onReveal(data) {
    this.stopTimer()

    const myPick      = data.picks?.[this.playerIdValue]
    const roundPoints = data.round_scores?.[this.playerIdValue] ?? 0
    this.totalScore   = data.scores?.[this.playerIdValue] ?? this.totalScore

    this.updateScore(this.totalScore)

    // Target color block
    const { r, g, b } = data.target_color
    if (this.hasTargetPreviewTarget)
      this.targetPreviewTarget.style.background = `rgb(${r},${g},${b})`

    // My pick color block (dark if no pick)
    if (this.hasMyPickPreviewTarget) {
      if (myPick) {
        this.myPickPreviewTarget.style.background = `rgb(${myPick.r},${myPick.g},${myPick.b})`
        this.myPickPreviewTarget.style.opacity    = "1"
      } else {
        this.myPickPreviewTarget.style.background = "rgb(30,30,30)"
        this.myPickPreviewTarget.style.opacity    = "0.5"
      }
    }

    if (this.hasRoundPointsLabelTarget)
      this.roundPointsLabelTarget.textContent = `+${roundPoints}`

    // Names: "It was Coral" under the target, "You made Salmon" with the score, and a streak bonus.
    if (this.hasTargetNameTarget)
      this.targetNameTarget.textContent = data.target_name ? t(`guess_the_color.colors.${data.target_name}`) : ""
    const made  = data.pick_names?.[this.playerIdValue]
    const bonus = data.bonuses?.[this.playerIdValue]
    if (this.hasPickNoteTarget) {
      this.pickNoteTarget.textContent = [
        made ? t("guess_the_color.you_made", { name: t(`guess_the_color.colors.${made}`) }) : "",
        bonus ? t("guess_the_color.streak_bonus", { count: data.streaks[this.playerIdValue], points: bonus }) : ""
      ].filter(Boolean).join(" · ")
    }

    // "94% match", or "🎯 Perfect!" when it's spot on
    const match = data.matches?.[this.playerIdValue]
    if (this.hasMatchLabelTarget) {
      this.matchLabelTarget.textContent = match == null ? "" :
        match >= (data.perfect ?? 97) ? t("guess_the_color.perfect") : t("guess_the_color.match", { percent: match })
      this.matchLabelTarget.style.color = match >= 85 ? "#4ade80" : match >= 60 ? "#facc15" : "#f87171"
    }

    this.showPhase("phaseReveal")
  }

  onGameOver(data) {
    this.stopTimer()
    const finalScore = data.scores?.[this.playerIdValue] ?? this.totalScore
    const sorted     = Object.entries(data.scores ?? {}).sort(([, a], [, b]) => b - a)
    const myRank     = sorted.findIndex(([id]) => id === this.playerIdValue) + 1

    if (this.hasGameOverTitleTarget)
      this.gameOverTitleTarget.textContent = placeTitle(myRank)

    if (this.hasFinalScoreTarget)
      this.finalScoreTarget.textContent = finalScore

    this.showPhase("phaseGameOver")
    if (isTopScore(data.scores, this.playerIdValue))
      celebrateWin(this.hasGameOverTitleTarget ? this.gameOverTitleTarget : null)
  }

  // ── Sliders: colour (hue), light, vivid ───────────────────────────────────

  sliders() {
    return [ this.sliderHueTarget, this.sliderLightTarget, this.sliderSatTarget ]
  }

  // Each round starts on a random colour at medium light and vividness, so no colour is favoured.
  resetSliders() {
    this.sliderHueTarget.value   = Math.floor(Math.random() * 360)
    this.sliderLightTarget.value = 50
    this.sliderSatTarget.value   = 70
    this.onSliderChange()
  }

  hsl() {
    return [ Number(this.sliderHueTarget.value), Number(this.sliderSatTarget.value), Number(this.sliderLightTarget.value) ]
  }

  // Paints the preview and each track's scale for the colour being mixed.
  onSliderChange() {
    if (this.submitted) return
    const [ h, s, l ] = this.hsl()
    const color = `hsl(${h} ${s}% ${l}%)`
    this.colorPreviewTarget.style.background = color
    this.sliders().forEach(slider => slider.style.setProperty("--gtc-color", color))

    const hues = Array.from({ length: 13 }, (_, i) => `hsl(${i * 30} ${s}% ${l}%)`).join(", ")
    this.sliderHueTarget.style.background   = `linear-gradient(to right, ${hues})`
    this.sliderLightTarget.style.background = `linear-gradient(to right, #000, hsl(${h} ${s}% 50%), #fff)`
    this.sliderSatTarget.style.background   = `linear-gradient(to right, hsl(${h} 0% ${l}%), hsl(${h} 100% ${l}%))`
  }

  // ── Submit ────────────────────────────────────────────────────────────────

  // Called automatically when the timer runs out — no manual button. The server takes {r, g, b}.
  submitColor() {
    if (this.submitted) return
    this.submitted = true

    const [ r, g, b ] = hslToRgb(...this.hsl())
    this.myPick = { r, g, b }
    this.channel?.perform("submit_color", { r, g, b })

    // Disable sliders so the player can't change after submission
    this.sliders().forEach(slider => { slider.disabled = true })

    // Show small confirmation label instead of navigating away
    if (this.hasSubmittedLabelTarget)
      this.submittedLabelTarget.classList.remove("hidden")
  }

  // ── Timer ─────────────────────────────────────────────────────────────────

  startCountdown(seconds) {
    let remaining = seconds
    if (this.hasPickingTimerTarget) this.pickingTimerTarget.textContent = remaining

    this.timerHandle = setInterval(() => {
      remaining--
      if (this.hasPickingTimerTarget)
        this.pickingTimerTarget.textContent = remaining > 0 ? remaining : ""

      if (remaining <= 0) {
        this.stopTimer()
        // Auto-submit with current slider values when time is up
        if (!this.submitted) this.submitColor()
      }
    }, 1000)
  }

  stopTimer() {
    clearInterval(this.timerHandle)
    this.timerHandle = null
  }

  // ── Helpers ───────────────────────────────────────────────────────────────

  showPhase(targetName) {
    const allPhases = ["phaseWaiting", "phaseWatch", "phasePicking", "phaseSubmitted", "phaseReveal", "phaseGameOver"]
    allPhases.forEach(name => {
      const capName = name.charAt(0).toUpperCase() + name.slice(1)
      if (this[`has${capName}Target`])
        this[`${name}Target`].classList.toggle("hidden", name !== targetName)
    })
  }

  updateScore(score) {
    if (this.hasScoreTarget) this.scoreTarget.textContent = score
  }
}

// h 0–360, s and l 0–100 → [r, g, b] 0–255
function hslToRgb(h, s, l) {
  s /= 100
  l /= 100
  const k = (n) => (n + h / 30) % 12
  const a = s * Math.min(l, 1 - l)
  const f = (n) => l - a * Math.max(-1, Math.min(k(n) - 3, 9 - k(n), 1))
  return [ f(0), f(8), f(4) ].map(v => Math.round(v * 255))
}
