import { Controller } from "@hotwired/stimulus"
import consumer from "channels/consumer"

const CELL_NEUTRAL  = "#1e3a5f"
const CELL_TAPPED   = "#facc15"
const CELL_SETTLED  = "#b45309"
const CELL_RADIUS   = "12px"
const GAP           = 8

const COLOR_GREEN   = "#4ade80"
const COLOR_YELLOW  = "#facc15"
const COLOR_RED     = "#f87171"

export default class extends Controller {
  static values  = { roomCode: String, playerId: String, gridSize: Number }
  static targets = [
    "phaseWaiting", "phaseWatching", "phaseInput", "phaseReveal", "phaseGameOver",
    "grid", "countdown", "tapProgress", "submittedLabel",
    "watchRoundLabel", "roundPointsLabel", "roundPointsDesc",
    "score", "gameOverTitle", "finalScore"
  ]

  connect() {
    this.taps        = []    // cell indices in tap order
    this.seqLength   = 0    // how many taps expected this round
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
    switch (data.action) {
      case "state_snapshot":   this.onStateSnapshot(data);  break
      case "show_sequence":    this.onShowSequence(data);   break
      case "player_turn":      this.onPlayerTurn(data);     break
      case "player_submitted":                              break
      case "reveal":           this.onReveal(data);         break
      case "game_over":        this.onGameOver(data);       break
      case "game_restarted":   window.location.reload();   break
    }
  }

  // ── Message handlers ──────────────────────────────────────────────────────

  onStateSnapshot(data) {
    const st = data.state || {}
    if (st.status === "game_over") this.showPhase("phaseGameOver")
    // All other statuses — stay on waiting phase (default visible)
  }

  onShowSequence(data) {
    const { round, total_rounds, sequence } = data
    this.seqLength = sequence.length
    this.watchRoundLabelTarget.textContent =
      `Round ${round} / ${total_rounds} · ${sequence.length} step${sequence.length > 1 ? "s" : ""}`
    this.showPhase("phaseWatching")
  }

  onPlayerTurn(data) {
    const { round, total_rounds, sequence_length, input_duration } = data

    clearInterval(this.timerHandle)
    this.seqLength = sequence_length
    this.taps      = []
    this.submitted = false

    this.submittedLabelTarget.classList.add("hidden")
    this.showPhase("phaseInput")   // must come first — buildGrid reads offsetWidth
    this.buildGrid()
    this.updateProgress()
    this.startCountdown(input_duration)
  }

  onReveal(data) {
    clearInterval(this.timerHandle)

    const myId    = this.playerIdValue
    const pts     = data.round_scores?.[myId] ?? 0
    const sub     = data.submissions?.[myId]
    const seq     = data.sequence || []
    const correct = this.countCorrect(seq, sub)

    this.totalScore = data.scores?.[myId] ?? this.totalScore
    this.scoreTarget.textContent = this.totalScore

    if (pts > 0) {
      this.roundPointsLabelTarget.textContent = `+${pts} pts`
      this.roundPointsLabelTarget.className   = "font-black text-4xl mb-1 text-green-400"
    } else {
      this.roundPointsLabelTarget.textContent = "0 pts"
      this.roundPointsLabelTarget.className   = "font-black text-4xl mb-1 text-slate-500"
    }

    // Dot bar: green = correct step, red = wrong/missing
    const dots = seq.map((cell, i) => {
      const prevMiss = seq.slice(0, i).some((c, j) => !Array.isArray(sub) || sub[j] !== c)
      const hit      = Array.isArray(sub) && sub[i] === cell && !prevMiss
      return `<span style="display:inline-block;width:14px;height:14px;border-radius:50%;
                background:${hit ? "#4ade80" : "#f87171"};margin:0 2px;"></span>`
    }).join("")

    this.roundPointsDescTarget.innerHTML =
      `<span class="block mb-2">${correct} / ${seq.length} correct steps</span>
       <span class="flex justify-center flex-wrap gap-1">${dots}</span>`

    this.showPhase("phaseReveal")
  }

  onGameOver(data) {
    clearInterval(this.timerHandle)

    const myId   = this.playerIdValue
    const scores = data.scores || {}
    const sorted = Object.entries(scores).sort((a, b) => b[1] - a[1])
    const rank   = sorted.findIndex(([id]) => id === myId) + 1
    const total  = scores[myId] ?? 0

    const titles = ["", "You won! 🥇", "2nd place 🥈", "3rd place 🥉"]
    this.gameOverTitleTarget.textContent = titles[rank] || `#${rank} place`
    this.finalScoreTarget.textContent    = total

    this.showPhase("phaseGameOver")
  }

  // ── Grid building ─────────────────────────────────────────────────────────

  buildGrid() {
    const size      = this.gridSizeValue
    const container = this.gridTarget

    // Fit grid to available screen width (phone)
    const availableW = Math.min(container.parentElement.offsetWidth - 32, 340)
    const cellSize   = Math.floor((availableW - GAP * (size - 1)) / size)

    container.style.gridTemplateColumns = `repeat(${size}, ${cellSize}px)`
    container.style.gap = `${GAP}px`
    container.innerHTML = ""

    for (let i = 0; i < size * size; i++) {
      const cell = document.createElement("div")
      cell.dataset.cellIndex = i
      cell.style.cssText = `
        width: ${cellSize}px;
        height: ${cellSize}px;
        background-color: ${CELL_NEUTRAL};
        border-radius: ${CELL_RADIUS};
        display: flex;
        align-items: center;
        justify-content: center;
        font-weight: 900;
        font-size: ${Math.round(cellSize * 0.35)}px;
        color: #0f172a;
        cursor: pointer;
        transition: background-color 0.08s ease, transform 0.08s ease;
        -webkit-tap-highlight-color: transparent;
      `
      cell.addEventListener("pointerdown", (e) => {
        e.preventDefault()
        this.tapCell(i)
      })
      container.appendChild(cell)
    }
  }

  getCell(index) {
    return this.gridTarget.querySelector(`[data-cell-index="${index}"]`)
  }

  // ── Tap handling ──────────────────────────────────────────────────────────

  tapCell(index) {
    if (this.submitted)               return
    if (this.taps.length >= this.seqLength) return

    this.taps.push(index)
    const tapNumber = this.taps.length

    // Flash yellow with tap order number
    const cell = this.getCell(index)
    if (cell) {
      cell.style.backgroundColor = CELL_TAPPED
      cell.style.transform       = "scale(0.92)"
      cell.textContent           = tapNumber

      setTimeout(() => {
        cell.style.backgroundColor = CELL_SETTLED
        cell.style.transform       = "scale(1)"
      }, 180)
    }

    this.updateProgress()

    // Auto-submit immediately once the full sequence is tapped
    if (this.taps.length >= this.seqLength) {
      setTimeout(() => this.submitSequence(), 250)
    }
  }

  updateProgress() {
    this.tapProgressTarget.textContent = `${this.taps.length} / ${this.seqLength} taps`
  }

  // ── Submit ────────────────────────────────────────────────────────────────

  submitSequence() {
    if (this.submitted) return
    this.submitted = true

    this.channel.perform("submit_sequence", { sequence: this.taps })

    // Disable all cells visually
    this.gridTarget.querySelectorAll("[data-cell-index]").forEach(cell => {
      cell.style.opacity = "0.45"
      cell.style.cursor  = "default"
    })

    this.submittedLabelTarget.classList.remove("hidden")
  }

  // ── Timer ─────────────────────────────────────────────────────────────────

  startCountdown(seconds) {
    clearInterval(this.timerHandle)
    let remaining = seconds
    this.countdownTarget.textContent = remaining
    this.countdownTarget.style.color = COLOR_GREEN

    this.timerHandle = setInterval(() => {
      remaining -= 1
      this.countdownTarget.textContent = remaining
      this.countdownTarget.style.color = this.countdownColor(remaining, seconds)

      if (remaining <= 0) {
        clearInterval(this.timerHandle)
        this.submitSequence()
      }
    }, 1000)
  }

  countdownColor(remaining, total) {
    const ratio = remaining / total
    if (ratio > 0.5)  return COLOR_GREEN
    if (ratio > 0.25) return COLOR_YELLOW
    return COLOR_RED
  }

  // ── Helpers ───────────────────────────────────────────────────────────────

  countCorrect(sequence, submission) {
    if (!Array.isArray(submission)) return 0
    let n = 0
    for (let i = 0; i < sequence.length; i++) {
      if (submission[i] !== sequence[i]) break
      n++
    }
    return n
  }

  showPhase(name) {
    const phases = [
      "phaseWaiting", "phaseWatching", "phaseInput", "phaseReveal", "phaseGameOver"
    ]
    phases.forEach(p => {
      const key = `has${p.charAt(0).toUpperCase() + p.slice(1)}Target`
      if (this[key]) this[`${p}Target`].classList.toggle("hidden", p !== name)
    })
  }
}
