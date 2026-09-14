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
    this.count        = 0
    this.submitted    = false
    this.timerHandle  = null
    this.totalScore   = 0
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
    switch (data.action) {
      case "state_snapshot":  this.onStateSnapshot(data);  break
      case "start_round":     this.onStartRound(data);     break
      case "player_submitted":                             break
      case "reveal":          this.onReveal(data);         break
      case "game_over":       this.onGameOver(data);       break
      case "game_restarted":  window.location.reload();    break
    }
  }

  // ── Message handlers ──────────────────────────────────────────────────────

  onStateSnapshot(data) {
    const st = data.state || {}
    if (st.status === "game_over") {
      this.showPhase("phaseGameOver")
    } else if (st.status === "counting") {
      // mid-round reconnect — just show waiting
      this.showPhase("phaseWaiting")
    }
    // Otherwise stay on waiting phase (default)
  }

  onStartRound(data) {
    clearInterval(this.timerHandle)
    this.count     = 0
    this.submitted = false
    this.duration  = data.duration

    this.countDisplayTarget.textContent = "0"
    this.submittedLabelTarget.classList.add("hidden")
    this.enableButtons()

    this.showPhase("phaseCounting")
    this.startCountdown(data.duration)
  }

  onReveal(data) {
    clearInterval(this.timerHandle)

    const myId    = this.playerIdValue
    const correct = data.bird_count
    const myPick  = data.picks?.[myId] ?? "—"
    const pts     = data.round_scores?.[myId] ?? 0

    this.totalScore = data.scores?.[myId] ?? this.totalScore

    this.correctCountTarget.textContent = correct
    this.myAnswerTarget.textContent     = myPick

    if (pts > 0) {
      this.roundPointsLabelTarget.textContent  = `+${pts} pts`
      this.roundPointsLabelTarget.className    = "font-black text-3xl mt-4 text-green-400"
    } else {
      this.roundPointsLabelTarget.textContent  = "0 pts"
      this.roundPointsLabelTarget.className    = "font-black text-3xl mt-4 text-slate-500"
    }

    this.scoreTarget.textContent = this.totalScore
    this.showPhase("phaseReveal")
  }

  onGameOver(data) {
    clearInterval(this.timerHandle)

    const myId    = this.playerIdValue
    const scores  = data.scores || {}
    const sorted  = Object.entries(scores).sort((a, b) => b[1] - a[1])
    const rank    = sorted.findIndex(([id]) => id === myId) + 1
    const total   = scores[myId] ?? 0

    const titles  = ["", "You won! 🥇", "2nd place 🥈", "3rd place 🥉"]
    this.gameOverTitleTarget.textContent = titles[rank] || `#${rank} place`
    this.finalScoreTarget.textContent    = total

    this.showPhase("phaseGameOver")
  }

  // ── Player actions ────────────────────────────────────────────────────────

  increment() {
    if (this.submitted) return
    this.count = Math.min(this.count + 1, 999)
    this.countDisplayTarget.textContent = this.count
  }

  decrement() {
    if (this.submitted) return
    this.count = Math.max(this.count - 1, 0)
    this.countDisplayTarget.textContent = this.count
  }

  // ── Timer & submit ────────────────────────────────────────────────────────

  startCountdown(seconds) {
    let remaining = seconds
    this.countdownTarget.textContent = remaining

    this.timerHandle = setInterval(() => {
      remaining -= 1
      this.countdownTarget.textContent = remaining

      if (remaining <= 0) {
        clearInterval(this.timerHandle)
        this.submitCount()
      }
    }, 1000)
  }

  submitCount() {
    if (this.submitted) return
    this.submitted = true

    this.channel.perform("submit_count", { count: this.count })

    this.disableButtons()
    this.submittedLabelTarget.classList.remove("hidden")
  }

  // ── Helpers ───────────────────────────────────────────────────────────────

  showPhase(name) {
    const phases = ["phaseWaiting", "phaseCounting", "phaseReveal", "phaseGameOver"]
    phases.forEach(p => {
      const target = `${p}Target`
      if (this.hasTarget(p)) {
        this[target].classList.toggle("hidden", p !== name)
      }
    })
  }

  hasTarget(name) {
    const key = `has${name.charAt(0).toUpperCase() + name.slice(1)}Target`
    return this[key]
  }

  enableButtons() {
    this.element.querySelectorAll("button[data-action*='increment'], button[data-action*='decrement']")
      .forEach(btn => btn.disabled = false)
  }

  disableButtons() {
    this.element.querySelectorAll("button[data-action*='increment'], button[data-action*='decrement']")
      .forEach(btn => btn.disabled = true)
  }
}
