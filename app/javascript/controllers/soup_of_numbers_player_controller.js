import { Controller } from "@hotwired/stimulus"
import consumer from "channels/consumer"

const CELL_EMPTY  = "#1e293b"
const CELL_MISSED = "#475569"
const CELL_WRONG  = "#dc2626"
const MY_FALLBACK = "#10b981"

// Countdown colour thresholds
const COLOR_GREEN  = "#4ade80"
const COLOR_YELLOW = "#facc15"
const COLOR_RED    = "#f87171"

const STYLE_ID = "soup-of-numbers-player-styles"
const STYLES = `
  @keyframes son-shake { 0%, 100% { transform: translateX(0) } 25% { transform: translateX(-6px) } 75% { transform: translateX(6px) } }
  @keyframes son-bounce { 0% { transform: scale(0.6); opacity: 0 } 60% { transform: scale(1.2); opacity: 1 } 100% { transform: scale(1) } }
  .son-shake  { animation: son-shake 0.25s ease-in-out 2 }
  .son-bounce { animation: son-bounce 0.45s ease-out }
`

export default class extends Controller {
  static values  = { roomCode: String, playerId: String }
  static targets = [
    "grid", "colorDot", "score", "status", "countdown", "feedback",
    "phaseGameOver", "gameOverTitle", "finalScore"
  ]

  connect() {
    this.timerHandle  = null
    this.grid         = []
    this.found        = []
    this.colors       = {}
    this.selection    = []     // [[row, col], …] in tap order
    this.active       = false  // a round is open and nobody has found the number yet
    this.pending      = false  // a claim is waiting for the server's answer
    this.targetLength = 0
    this.clickSound   = new Audio("/games/sounds/click.mp3")
    this.injectStyles()
    this.subscribe()
  }

  disconnect() {
    this.channel?.unsubscribe()
    clearInterval(this.timerHandle)
    this.audioCtx?.close()
  }

  subscribe() {
    this.channel = consumer.subscriptions.create({
      channel:   "Games::SoupOfNumbersChannel",
      room_code: this.roomCodeValue,
      player_id: this.playerIdValue
    }, {
      received: (data) => this.handleMessage(data)
    })
  }

  handleMessage(data) {
    switch (data.action) {
      case "state_snapshot":  this.onSnapshot(data);     break
      case "new_round":       this.onNewRound(data);     break
      case "number_found":    this.onNumberFound(data);  break
      case "number_missed":   this.onNumberMissed(data); break
      case "claim_rejected":  this.onClaimRejected();       break
      case "game_over":       this.onGameOver(data);     break
      case "game_restarted":  window.location.reload();  break
      case "game_changed":    window.location.href = `/rooms/${this.roomCodeValue}`; break
    }
  }

  // ── Message handlers ──────────────────────────────────────────────────────

  onSnapshot({ state }) {
    this.grid   = state.grid || []
    this.found  = state.found || []
    this.colors = state.colors || {}

    this.colorDotTarget.style.background = this.myColor()
    this.scoreTarget.textContent = state.scores?.[this.playerIdValue] ?? 0
    this.buildGrid()
    this.paint()

    if (state.status === "searching" && state.target) {
      this.openRound(state.round, state.total_rounds, state.target.length)
      this.startCountdown(Math.max(Math.round(state.round_ends_at - Date.now() / 1000), 0), state.round_time)
    } else if (state.status === "game_over") {
      this.onGameOver({ scores: state.scores || {} })
    }
  }

  onNewRound({ round, total_rounds, duration, target }) {
    this.openRound(round, total_rounds, target.length)
    this.startCountdown(duration)
  }

  onNumberFound(data) {
    this.closeRound()
    if (data.color) this.colors[data.player_id] = data.color
    this.found.push({ number: data.number, cells: data.cells, player_id: data.player_id })
    this.paint()

    this.scoreTarget.textContent = data.scores?.[this.playerIdValue] ?? this.scoreTarget.textContent
    const mine = data.player_id === this.playerIdValue
    if (mine) {
      this.playChime()
      this.vibrate([ 60, 40, 120 ])
    }
    this.setFeedback(mine ? `🎉 You found it! +${data.points}` : `${this.esc(data.nickname)} found ${data.number}`,
                     mine ? COLOR_GREEN : data.color)
  }

  onNumberMissed(data) {
    this.closeRound()
    this.found.push({ number: data.number, cells: data.cells, player_id: null })
    this.paint()
    this.setFeedback(`⏰ Nobody found ${data.number}`, "#94a3b8")
  }

  // Ignored once the round closed: the "found by" message stays on screen.
  onClaimRejected() {
    if (!this.active) return
    this.pending = false
    this.rejectSelection("✗ Not the number")
  }

  onGameOver({ scores }) {
    this.closeRound()
    const ranking = Object.entries(scores || {}).sort((a, b) => b[1] - a[1])
    const place   = ranking.findIndex(([id]) => id === this.playerIdValue) + 1
    const myScore = scores?.[this.playerIdValue] ?? 0

    this.gameOverTitleTarget.textContent = place === 1 ? "🥇 You won!" : place > 0 ? `#${place} place` : "Game over"
    this.finalScoreTarget.textContent    = myScore
    this.phaseGameOverTarget.classList.remove("hidden")
  }

  openRound(round, totalRounds, length) {
    this.active       = true
    this.pending      = false
    this.selection    = []
    this.targetLength = length
    this.statusTarget.textContent = `Round ${round}/${totalRounds} · Find the ${length}-digit number`
    this.setFeedback("")
    this.paint()
  }

  closeRound() {
    this.active    = false
    this.pending   = false
    this.selection = []
    this.stopCountdown()
    this.countdownTarget.textContent = ""
  }

  // ── Selection ─────────────────────────────────────────────────────────────

  // Tap step by step, or tap the first and the last digit: both build a straight line.
  // Anything that can't become the target's length clears the selection.
  tap(event) {
    const cell = event.target.closest("[data-cell]")
    if (!cell || !this.active || this.pending) return

    const r   = Number(cell.dataset.row)
    const c   = Number(cell.dataset.col)
    const sel = this.selection
    const at  = sel.findIndex(([sr, sc]) => sr === r && sc === c)

    if (at !== -1) {
      if (at === sel.length - 1) {   // tapping the last digit again undoes it
        sel.pop()
        this.paint()
      } else {
        this.rejectSelection()
      }
      return
    }

    const line = this.extendLine(sel, r, c)
    if (!line) return this.rejectSelection("✗ Not a straight line")
    if (line.length > this.targetLength) return this.rejectSelection(`✗ The number has ${this.targetLength} digits`)

    this.selection = line
    this.setFeedback("")
    this.paint()
    this.playClick()

    if (line.length === this.targetLength) {
      this.pending = true
      this.channel.perform("claim_number", { cells: line })
    }
  }

  // Returns the selection with (r, c) added — filling any gap along the line — or null.
  extendLine(sel, r, c) {
    if (sel.length === 0) return [[r, c]]

    const [r0, c0] = sel[0]
    if (sel.length === 1) {
      const dr = r - r0, dc = c - c0
      if (!(dr === 0 || dc === 0 || Math.abs(dr) === Math.abs(dc))) return null
      const steps = Math.max(Math.abs(dr), Math.abs(dc))
      return this.walk(r0, c0, Math.sign(dr), Math.sign(dc), steps)
    }

    const sr = sel[1][0] - r0, sc = sel[1][1] - c0
    const [lr, lc] = sel[sel.length - 1]
    const k = sr !== 0 ? (r - lr) / sr : (c - lc) / sc
    if (!Number.isInteger(k) || k < 1 || r !== lr + sr * k || c !== lc + sc * k) return null
    return sel.concat(this.walk(lr, lc, sr, sc, k).slice(1))
  }

  walk(r, c, dr, dc, steps) {
    return Array.from({ length: steps + 1 }, (_, i) => [r + dr * i, c + dc * i])
  }

  rejectSelection(message = "") {
    const cells = this.selection
    this.selection = []
    cells.forEach(([r, c]) => {
      const el = this.cellAt(r, c)
      if (el) el.style.background = CELL_WRONG
    })
    if (message) this.setFeedback(message, COLOR_RED)
    this.vibrate(150)
    this.restartAnimation(this.gridTarget, "son-shake")
    setTimeout(() => this.paint(), 250)
  }

  // ── Grid ──────────────────────────────────────────────────────────────────

  buildGrid() {
    const size = this.grid.length
    const el   = this.gridTarget
    el.style.gridTemplateColumns = `repeat(${size}, minmax(0, 1fr))`
    el.innerHTML = ""

    this.grid.forEach((row, r) => {
      [...row].forEach((digit, c) => {
        const cell = document.createElement("div")
        cell.dataset.cell = ""
        cell.dataset.row  = r
        cell.dataset.col  = c
        cell.textContent  = digit
        cell.style.cssText = `
          aspect-ratio: 1;
          display: flex; align-items: center; justify-content: center;
          border-radius: 6px;
          font-family: ui-monospace, monospace;
          font-weight: 900;
          font-size: calc(min(100vw - 1.5rem, 70vh) / ${size} * 0.55);
          transition: background-color 0.12s ease, transform 0.12s ease;
        `
        el.appendChild(cell)
      })
    })
  }

  // Found numbers in their finder's colour (faded), the current selection solid in my colour.
  paint() {
    const fills = {}
    this.found.forEach(entry => {
      const color = entry.player_id ? (this.colors[entry.player_id] || CELL_MISSED) : CELL_MISSED
      entry.cells.forEach(([r, c]) => { fills[`${r}-${c}`] = color })
    })
    const selected = new Set(this.selection.map(([r, c]) => `${r}-${c}`))

    this.gridTarget.querySelectorAll("[data-cell]").forEach(el => {
      const key = `${el.dataset.row}-${el.dataset.col}`
      if (selected.has(key)) {
        el.style.background = this.myColor()
        el.style.color      = "#fff"
        el.style.transform  = "scale(1.08)"
      } else {
        el.style.background = fills[key] ? `${fills[key]}99` : CELL_EMPTY
        el.style.color      = fills[key] ? "#fff" : "#cbd5e1"
        el.style.transform  = "scale(1)"
      }
    })
  }

  cellAt(r, c) {
    return this.gridTarget.querySelector(`[data-row="${r}"][data-col="${c}"]`)
  }

  myColor() {
    return this.colors[this.playerIdValue] || MY_FALLBACK
  }

  setFeedback(html, color = "#fff") {
    this.feedbackTarget.innerHTML   = html
    this.feedbackTarget.style.color = color
    if (html) this.restartAnimation(this.feedbackTarget, "son-bounce")
  }

  // ── Countdown ─────────────────────────────────────────────────────────────

  startCountdown(seconds, total = seconds) {
    this.stopCountdown()
    let remaining = seconds
    this.renderCountdown(remaining, total)

    this.timerHandle = setInterval(() => {
      remaining -= 1
      this.renderCountdown(Math.max(remaining, 0), total)
      if (remaining <= 0) this.stopCountdown()
    }, 1000)
  }

  stopCountdown() {
    clearInterval(this.timerHandle)
    this.timerHandle = null
  }

  renderCountdown(remaining, total) {
    const ratio = remaining / total
    this.countdownTarget.textContent = remaining
    this.countdownTarget.style.color = ratio > 0.5 ? COLOR_GREEN : ratio > 0.25 ? COLOR_YELLOW : COLOR_RED
  }

  // ── Sound & feel ──────────────────────────────────────────────────────────

  playClick() {
    this.clickSound.currentTime = 0
    this.clickSound.play().catch(() => {}) // ignore autoplay blocks
  }

  // Short rising two-note chime, synthesized so no extra sound file is needed.
  playChime() {
    try {
      this.audioCtx ??= new AudioContext()
      const ctx = this.audioCtx
      ;[ 880, 1320 ].forEach((freq, i) => {
        const osc  = ctx.createOscillator()
        const gain = ctx.createGain()
        const at   = ctx.currentTime + i * 0.12
        osc.type = "triangle"
        osc.frequency.value = freq
        gain.gain.setValueAtTime(0.0001, at)
        gain.gain.exponentialRampToValueAtTime(0.4, at + 0.02)
        gain.gain.exponentialRampToValueAtTime(0.0001, at + 0.4)
        osc.connect(gain).connect(ctx.destination)
        osc.start(at)
        osc.stop(at + 0.45)
      })
    } catch (_) { /* audio unavailable */ }
  }

  vibrate(pattern) {
    navigator.vibrate?.(pattern)
  }

  restartAnimation(el, className) {
    el.classList.remove(className)
    void el.offsetWidth // force reflow so the animation plays again
    el.classList.add(className)
  }

  injectStyles() {
    if (document.getElementById(STYLE_ID)) return
    const style = document.createElement("style")
    style.id = STYLE_ID
    style.textContent = STYLES
    document.head.appendChild(style)
  }

  esc(str) {
    return String(str).replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;")
  }
}
