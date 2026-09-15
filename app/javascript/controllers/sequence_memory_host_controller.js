import { Controller } from "@hotwired/stimulus"
import consumer from "channels/consumer"

const CELL_NEUTRAL   = "#1e3a5f"
const CELL_HIGHLIGHT = "#facc15"
const CELL_SEQUENCE  = "#f59e0b"
const CELL_RADIUS    = "14px"

const CELL_SIZE = { 3: 120, 4: 96, 6: 68 }
const GAP_SIZE  = { 3: 14,  4: 12, 6: 10 }

// Countdown colour thresholds
const COLOR_GREEN  = "#4ade80"
const COLOR_YELLOW = "#facc15"
const COLOR_RED    = "#f87171"

export default class extends Controller {
  static values  = { roomCode: String, gridSize: Number }
  static targets = [
    "phaseWaiting", "phaseWatching", "phaseInput", "phaseReveal", "phaseGameOver",
    "grid", "grid2", "revealGrid",
    "roundLabel", "roundLabel2", "roundLabel3",
    "stepIndicator", "submittedCount",
    "countdown", "playerResults", "finalLeaderboard", "playAgain"
  ]

  connect() {
    this.timerHandle    = null
    this.submittedCount = 0
    this.inputDuration  = 0
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
    switch (data.action) {
      case "show_sequence":    this.onShowSequence(data);    break
      case "player_turn":      this.onPlayerTurn(data);      break
      case "player_submitted": this.onPlayerSubmitted(data); break
      case "reveal":           this.onReveal(data);          break
      case "game_over":        this.onGameOver(data);        break
      case "game_restarted":   window.location.reload();     break
      case "game_changed":     window.location.href = `/rooms/${this.roomCodeValue}`; break
    }
  }

  // ── Message handlers ──────────────────────────────────────────────────────

  onShowSequence(data) {
    const { round, total_rounds, sequence, flash_duration, flash_gap } = data

    const steps = sequence.length
    this.roundLabelTarget.textContent =
      `Round ${round} / ${total_rounds} · ${steps} step${steps > 1 ? "s" : ""}`
    this.stepIndicatorTarget.textContent = ""

    this.buildGrid(this.gridTarget)
    this.showPhase("phaseWatching")

    setTimeout(() => {
      this.animateSequence(this.gridTarget, sequence, flash_duration, flash_gap)
    }, 600)
  }

  onPlayerTurn(data) {
    const { round, total_rounds, input_duration } = data

    this.submittedCount    = 0
    this.inputDuration     = input_duration
    this.roundLabel2Target.textContent       = `Round ${round} / ${total_rounds}`
    this.submittedCountTarget.textContent    = ""

    this.buildGrid(this.grid2Target)
    this.showPhase("phaseInput")
    this.startCountdown(this.countdownTarget, input_duration)
  }

  onPlayerSubmitted(data) {
    this.submittedCount++
    this.submittedCountTarget.textContent =
      `${this.submittedCount} player${this.submittedCount > 1 ? "s" : ""} submitted`
  }

  onReveal(data) {
    clearInterval(this.timerHandle)
    const { round, total_rounds, sequence } = data

    this.roundLabel3Target.textContent = `Round ${round} / ${total_rounds}`
    this.buildRevealGrid(this.revealGridTarget, sequence)
    this.playerResultsTarget.innerHTML = this.buildPlayerResults(data)

    this.showPhase("phaseReveal")
  }

  onGameOver(data) {
    this.finalLeaderboardTarget.innerHTML = this.buildLeaderboard(data)
    this.playAgainTarget.addEventListener("click", () => {
      this.channel.perform("restart_game", {})
    }, { once: true })
    this.showPhase("phaseGameOver")
  }

  // ── Grid building ─────────────────────────────────────────────────────────

  buildGrid(container, cellSizePx = null) {
    const size = this.gridSizeValue
    const cs   = cellSizePx ?? (CELL_SIZE[size] || 80)
    const gap  = GAP_SIZE[size] || 10

    container.style.gridTemplateColumns = `repeat(${size}, ${cs}px)`
    container.style.gap = `${gap}px`
    container.innerHTML = ""

    for (let i = 0; i < size * size; i++) {
      const cell = document.createElement("div")
      cell.dataset.cellIndex = i
      cell.style.cssText = `
        width: ${cs}px;
        height: ${cs}px;
        background-color: ${CELL_NEUTRAL};
        border-radius: ${CELL_RADIUS};
        box-shadow: inset 0 2px 6px rgba(0,0,0,0.4), 0 1px 3px rgba(0,0,0,0.6);
        transition: background-color 0.08s ease, transform 0.1s ease;
        display: flex;
        align-items: center;
        justify-content: center;
        font-weight: 900;
        font-size: ${Math.round(cs * 0.3)}px;
        color: #0f172a;
      `
      container.appendChild(cell)
    }
  }

  buildRevealGrid(container, sequence) {
    const size = this.gridSizeValue
    const cs   = Math.round((CELL_SIZE[size] || 80) * 0.62)
    this.buildGrid(container, cs)

    sequence.forEach((cellIndex, i) => {
      const cell = this.getCell(container, cellIndex)
      if (!cell) return
      cell.style.backgroundColor = CELL_SEQUENCE
      cell.style.boxShadow = `0 0 12px rgba(245,158,11,0.6)`
      cell.textContent = i + 1
    })
  }

  getCell(container, index) {
    return container.querySelector(`[data-cell-index="${index}"]`)
  }

  // ── Sequence animation ────────────────────────────────────────────────────

  animateSequence(container, sequence, flashDuration, flashGap) {
    const flashMs = Math.round(flashDuration * 1000)
    const gapMs   = Math.round(flashGap * 1000)
    const total   = sequence.length

    let delay = 0
    sequence.forEach((cellIndex, step) => {
      // Update step indicator just before the flash
      setTimeout(() => {
        this.stepIndicatorTarget.textContent = `Step ${step + 1} / ${total}`
      }, delay)

      // Light up + pulse
      setTimeout(() => {
        const cell = this.getCell(container, cellIndex)
        if (!cell) return
        cell.style.backgroundColor = CELL_HIGHLIGHT
        cell.style.transform       = "scale(1.1)"
        cell.style.boxShadow       = `0 0 24px rgba(250,204,21,0.7), inset 0 2px 6px rgba(0,0,0,0.2)`
      }, delay)

      // Return to neutral
      setTimeout(() => {
        const cell = this.getCell(container, cellIndex)
        if (!cell) return
        cell.style.backgroundColor = CELL_NEUTRAL
        cell.style.transform       = "scale(1)"
        cell.style.boxShadow       = `inset 0 2px 6px rgba(0,0,0,0.4), 0 1px 3px rgba(0,0,0,0.6)`
      }, delay + flashMs)

      delay += flashMs + gapMs
    })

    // Clear step indicator after last flash
    setTimeout(() => {
      this.stepIndicatorTarget.textContent = "Done!"
    }, delay)
  }

  // ── Countdown ─────────────────────────────────────────────────────────────

  startCountdown(el, seconds) {
    clearInterval(this.timerHandle)
    let remaining = seconds
    el.textContent  = remaining
    el.style.color  = COLOR_GREEN

    this.timerHandle = setInterval(() => {
      remaining -= 1
      el.textContent = remaining
      el.style.color = this.countdownColor(remaining, seconds)
      if (remaining <= 0) clearInterval(this.timerHandle)
    }, 1000)
  }

  countdownColor(remaining, total) {
    const ratio = remaining / total
    if (ratio > 0.5)  return COLOR_GREEN
    if (ratio > 0.25) return COLOR_YELLOW
    return COLOR_RED
  }

  // ── HTML builders ─────────────────────────────────────────────────────────

  buildPlayerResults(data) {
    const { sequence, submissions, round_scores, nicknames } = data
    const seqLen = sequence.length

    return Object.entries(round_scores || {})
      .sort((a, b) => b[1] - a[1])
      .map(([id, pts]) => {
        const name    = nicknames?.[id] || id
        const sub     = submissions?.[id]
        const correct = this.countCorrect(sequence, sub)
        const dotBar  = this.buildDotBar(sequence, sub)
        const ptColor = pts > 0 ? "text-green-400" : "text-slate-500"
        return `
          <div class="bg-white/10 backdrop-blur-sm rounded-2xl px-4 py-3 text-center min-w-[110px]">
            <p class="text-white text-xs font-mono truncate max-w-[100px] mx-auto">${this.esc(name)}</p>
            <div class="flex gap-1 justify-center mt-2 mb-1">${dotBar}</div>
            <p class="text-white font-black text-lg">${correct}<span class="text-slate-500 text-xs font-normal"> / ${seqLen}</span></p>
            <p class="${ptColor} text-xs font-bold">+${pts} pts</p>
          </div>`
      }).join("")
  }

  // Dot bar: green dot per correct step, red dot per wrong/missing step
  buildDotBar(sequence, submission) {
    return sequence.map((cell, i) => {
      const hit = Array.isArray(submission) && submission[i] === cell
      // Stop marking correct after first miss (partial credit rule)
      const prevMiss = Array.isArray(submission) &&
        sequence.slice(0, i).some((c, j) => submission[j] !== c)
      const color = (!prevMiss && hit) ? "#4ade80" : "#f87171"
      return `<span style="
        display:inline-block;width:10px;height:10px;
        border-radius:50%;background:${color};
      "></span>`
    }).join("")
  }

  buildLeaderboard(data) {
    const { scores, nicknames } = data
    const medals = ["🥇", "🥈", "🥉"]
    return Object.entries(scores || {})
      .sort((a, b) => b[1] - a[1])
      .map(([id, pts], i) => {
        const name  = nicknames?.[id] || id
        const medal = medals[i] || `#${i + 1}`
        return `
          <div class="flex items-center justify-between bg-slate-800 rounded-xl px-5 py-3">
            <span class="text-2xl w-8">${medal}</span>
            <span class="flex-1 text-white font-bold ml-3 truncate">${this.esc(name)}</span>
            <span class="font-mono font-black text-yellow-400 text-lg">${pts}</span>
          </div>`
      }).join("")
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
    const phases = ["phaseWaiting", "phaseWatching", "phaseInput", "phaseReveal", "phaseGameOver"]
    phases.forEach(p => {
      const key = `has${p.charAt(0).toUpperCase() + p.slice(1)}Target`
      if (this[key]) this[`${p}Target`].classList.toggle("hidden", p !== name)
    })
  }

  esc(str) {
    return String(str).replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;")
  }
}
