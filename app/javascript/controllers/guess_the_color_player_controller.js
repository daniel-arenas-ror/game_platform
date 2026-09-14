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
    this.timerHandle = null
    this.submitted   = false
    this.myPick      = null
    this.totalScore  = 0
    this.subscribe()
    this.bindSliders()
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
    }
  }

  // ── Phase handlers ────────────────────────────────────────────────────────

  applySnapshot(state) {
    if (!state) return
    this.totalScore = state.scores?.[this.playerIdValue] ?? 0
    this.updateScore(this.totalScore)

    switch (state.status) {
      case "showing_color": this.showPhase("phaseWatch");      break
      case "picking":       this.showPhase("phasePicking");    break
      case "revealing":     this.showPhase("phaseSubmitted");  break
      case "game_over":     this.showPhase("phaseGameOver");   break
      default:              this.showPhase("phaseWaiting");
    }
  }

  onShowColor(data) {
    this.stopTimer()
    this.submitted = false
    this.myPick    = null
    // Reset sliders to mid-grey
    this.setSliderValues(128, 128, 128)
    this.showPhase("phaseWatch")
  }

  onStartPicking(data) {
    this.stopTimer()
    this.submitted = false
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

    this.showPhase("phaseReveal")
  }

  onGameOver(data) {
    this.stopTimer()
    const finalScore = data.scores?.[this.playerIdValue] ?? this.totalScore
    const sorted     = Object.entries(data.scores ?? {}).sort(([, a], [, b]) => b - a)
    const myRank     = sorted.findIndex(([id]) => id === this.playerIdValue) + 1

    const titles = { 1: "🥇 You Win!", 2: "🥈 2nd Place", 3: "🥉 3rd Place" }
    if (this.hasGameOverTitleTarget)
      this.gameOverTitleTarget.textContent = titles[myRank] ?? `#${myRank} Place`

    if (this.hasFinalScoreTarget)
      this.finalScoreTarget.textContent = finalScore

    this.showPhase("phaseGameOver")
  }

  // ── Sliders ───────────────────────────────────────────────────────────────

  bindSliders() {
    if (this.hasSliderRTarget) this.sliderRTarget.addEventListener("input", () => this.onSliderChange())
    if (this.hasSliderGTarget) this.sliderGTarget.addEventListener("input", () => this.onSliderChange())
    if (this.hasSliderBTarget) this.sliderBTarget.addEventListener("input", () => this.onSliderChange())
  }

  onSliderChange() {
    if (this.submitted) return
    const r = this.sliderRTarget.value
    const g = this.sliderGTarget.value
    const b = this.sliderBTarget.value

    if (this.hasValueRTarget) this.valueRTarget.textContent = r
    if (this.hasValueGTarget) this.valueGTarget.textContent = g
    if (this.hasValueBTarget) this.valueBTarget.textContent = b

    if (this.hasColorPreviewTarget)
      this.colorPreviewTarget.style.background = `rgb(${r},${g},${b})`
  }

  setSliderValues(r, g, b) {
    if (this.hasSliderRTarget) { this.sliderRTarget.value = r; if (this.hasValueRTarget) this.valueRTarget.textContent = r }
    if (this.hasSliderGTarget) { this.sliderGTarget.value = g; if (this.hasValueGTarget) this.valueGTarget.textContent = g }
    if (this.hasSliderBTarget) { this.sliderBTarget.value = b; if (this.hasValueBTarget) this.valueBTarget.textContent = b }
    if (this.hasColorPreviewTarget)
      this.colorPreviewTarget.style.background = `rgb(${r},${g},${b})`
  }

  // ── Submit ────────────────────────────────────────────────────────────────

  submitColor() {
    if (this.submitted) return
    this.submitted = true

    const r = parseInt(this.sliderRTarget.value)
    const g = parseInt(this.sliderGTarget.value)
    const b = parseInt(this.sliderBTarget.value)
    this.myPick = { r, g, b }

    this.channel?.perform("submit_color", { r, g, b })

    // Show submitted state
    if (this.hasSubmittedPreviewTarget)
      this.submittedPreviewTarget.style.background = `rgb(${r},${g},${b})`

    this.stopTimer()
    this.showPhase("phaseSubmitted")
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
