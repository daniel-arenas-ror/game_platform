import { Controller } from "@hotwired/stimulus"
import consumer from "channels/consumer"
import { t } from "controllers/shared/i18n"

const CELL_EMPTY  = "#1e293b"
const CELL_MISSED = "#475569"

// Countdown colour thresholds
const COLOR_GREEN  = "#4ade80"
const COLOR_YELLOW = "#facc15"
const COLOR_RED    = "#f87171"

// Tick sound plays once per second during the last seconds of a round
const TICK_FROM = 5

const STYLE_ID = "soup-of-numbers-host-styles"
const STYLES = `
  @keyframes son-pop-in { 0% { transform: scale(0.4); opacity: 0 } 70% { transform: scale(1.15); opacity: 1 } 100% { transform: scale(1) } }
  @keyframes son-slide-up { from { transform: translateY(12px); opacity: 0 } to { transform: translateY(0); opacity: 1 } }
  @keyframes son-glow { 0%, 100% { box-shadow: 0 0 0 rgba(255,255,255,0) } 50% { box-shadow: 0 0 18px rgba(255,255,255,0.8) } }
  .son-pop-in   { animation: son-pop-in 0.5s ease-out }
  .son-slide-up { animation: son-slide-up 0.35s ease-out }
  .son-glow     { animation: son-glow 0.6s ease-in-out 2 }
`

export default class extends Controller {
  static values  = { roomCode: String }
  static targets = [
    "grid", "roundLabel",
    "targetTitle", "targetNumber", "targetMeta", "countdown", "banner",
    "scoreboard", "foundList",
    "phaseGameOver", "finalLeaderboard", "playAgain"
  ]

  connect() {
    this.timerHandle = null
    this.grid      = []
    this.found     = []
    this.colors    = {}
    this.scores    = {}
    this.nicknames = {}
    this.tickSound = new Audio("/games/sounds/timer_count_down.mp3")
    this.injectStyles()
    this.subscribe()
  }

  disconnect() {
    this.winSound?.pause()
    this.stopCountdown()
    this.channel?.unsubscribe()
    this.audioCtx?.close()
  }

  subscribe() {
    this.channel = consumer.subscriptions.create({
      channel:   "Games::SoupOfNumbersChannel",
      room_code: this.roomCodeValue,
      player_id: ""
    }, {
      connected: () => this.channel.perform("start_game_loop", {}),
      received:  (data) => this.handleMessage(data)
    })
  }

  handleMessage(data) {
    switch (data.action) {
      case "state_snapshot":  this.onSnapshot(data);    break
      case "new_round":       this.onNewRound(data);    break
      case "number_found":    this.onNumberFound(data); break
      case "number_missed":   this.onNumberMissed(data); break
      case "player_left":     this.onPlayerLeft(data);  break
      case "game_over":       this.onGameOver(data);    break
      case "game_error":      this.showBanner(t("soup_of_numbers.error"), CELL_MISSED); break
      case "game_restarted":  window.location.reload(); break
      case "game_changed":    window.location.href = `/rooms/${this.roomCodeValue}`; break
    }
  }

  // ── Message handlers ──────────────────────────────────────────────────────

  onSnapshot({ state, nicknames }) {
    this.grid      = state.grid || []
    this.found     = state.found || []
    this.colors    = state.colors || {}
    this.scores    = state.scores || {}
    this.nicknames = nicknames || {}

    this.buildGrid()
    this.found.forEach(entry => this.paintEntry(entry))
    this.renderScoreboard()
    this.renderFoundList()
    this.setRoundLabel(state.round, state.total_rounds)

    if (state.status === "searching" && state.target) {
      this.showTarget(state.target)
      this.startCountdown(Math.max(Math.round(state.round_ends_at - Date.now() / 1000), 0), state.round_time)
    } else if (state.status === "game_over") {
      this.onGameOver({ scores: this.scores, nicknames: this.nicknames })
    }
  }

  onNewRound({ round, total_rounds, duration, target }) {
    this.setRoundLabel(round, total_rounds)
    this.bannerTarget.classList.add("hidden")
    this.showTarget(target)
    this.startCountdown(duration)
  }

  onNumberFound(data) {
    this.stopCountdown()
    this.scores = data.scores || this.scores
    if (data.color) this.colors[data.player_id] = data.color
    this.nicknames[data.player_id] = data.nickname

    const entry = { number: data.number, cells: data.cells, player_id: data.player_id }
    this.found.push(entry)
    this.paintEntry(entry, true)
    this.renderScoreboard()
    this.renderFoundList()
    this.playChime()
    this.showBanner(t("soup_of_numbers.found_it", { name: this.esc(data.nickname), points: data.points }), data.color)
  }

  onNumberMissed(data) {
    this.stopCountdown()
    const entry = { number: data.number, cells: data.cells, player_id: null }
    this.found.push(entry)
    this.paintEntry(entry, true)
    this.renderFoundList()
    this.showBanner(t("soup_of_numbers.nobody"), CELL_MISSED)
  }

  onPlayerLeft({ player_id }) {
    delete this.scores[player_id]
    this.renderScoreboard()
  }

  onGameOver(data) {
    this.stopCountdown()
    this.winSound = new Audio("/games/sounds/Triumphant_win.mp3")
    this.winSound.play().catch(() => {}) // ignore autoplay blocks
    this.finalLeaderboardTarget.innerHTML = this.buildLeaderboard(data.scores || this.scores, data.nicknames || this.nicknames)
    this.playAgainTarget.addEventListener("click", () => {
      this.channel.perform("restart_game", {})
    }, { once: true })
    this.phaseGameOverTarget.classList.remove("hidden")
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
        cell.dataset.cell = `${r}-${c}`
        cell.textContent  = digit
        cell.style.cssText = `
          aspect-ratio: 1;
          display: flex; align-items: center; justify-content: center;
          border-radius: 8px;
          background: ${CELL_EMPTY};
          color: #cbd5e1;
          font-family: ui-monospace, monospace;
          font-weight: 900;
          font-size: calc(min(80vh, 60vw) / ${size} * 0.5);
          transition: background-color 0.3s ease, transform 0.3s ease;
        `
        el.appendChild(cell)
      })
    })
  }

  paintEntry(entry, animate = false) {
    const color = entry.player_id ? (this.colors[entry.player_id] || CELL_MISSED) : CELL_MISSED
    entry.cells.forEach(([r, c], i) => {
      const cell = this.gridTarget.querySelector(`[data-cell="${r}-${c}"]`)
      if (!cell) return
      cell.style.background = color
      cell.style.color      = "#fff"
      if (animate) {
        setTimeout(() => { cell.style.transform = "scale(1.25)"; this.restartAnimation(cell, "son-glow") }, i * 80)
        setTimeout(() => { cell.style.transform = "scale(1)" }, i * 80 + 300)
      }
    })
  }

  // ── Sidebar ───────────────────────────────────────────────────────────────

  showTarget(target) {
    this.targetTitleTarget.textContent  = t("soup_of_numbers.find_this")
    this.targetNumberTarget.textContent = target.number
    this.targetMetaTarget.textContent   = t("soup_of_numbers.target_meta", { length: target.length, points: target.points })
    this.restartAnimation(this.targetNumberTarget, "son-pop-in")
  }

  showBanner(html, color) {
    this.bannerTarget.innerHTML        = html
    this.bannerTarget.style.background = color
    this.bannerTarget.classList.remove("hidden")
    this.restartAnimation(this.bannerTarget, "son-slide-up")
  }

  setRoundLabel(round, total) {
    this.roundLabelTarget.textContent = round ? t("soup_of_numbers.round", { round, total }) : ""
  }

  renderScoreboard() {
    this.scoreboardTarget.innerHTML = Object.entries(this.scores)
      .sort((a, b) => b[1] - a[1])
      .map(([id, pts]) => `
        <div class="flex items-center gap-3">
          <span class="w-3 h-3 rounded-full shrink-0" style="background:${this.colors[id] || CELL_MISSED}"></span>
          <span class="flex-1 font-bold truncate">${this.esc(this.nicknames[id] || "?")}</span>
          <span class="font-mono font-black text-emerald-400">${pts}</span>
        </div>`).join("")
  }

  renderFoundList() {
    if (this.found.length === 0) return
    this.foundListTarget.innerHTML = this.found.map(entry => {
      const color = entry.player_id ? (this.colors[entry.player_id] || CELL_MISSED) : CELL_MISSED
      return `<span class="px-3 py-1 rounded-lg font-mono font-black text-sm" style="background:${color}">${this.esc(entry.number)}</span>`
    }).join("")
  }

  buildLeaderboard(scores, nicknames) {
    const medals = ["🥇", "🥈", "🥉"]
    return Object.entries(scores || {})
      .sort((a, b) => b[1] - a[1])
      .map(([id, pts], i) => `
        <div class="flex items-center justify-between bg-slate-800 rounded-xl px-5 py-3">
          <span class="text-2xl w-8">${medals[i] || `#${i + 1}`}</span>
          <span class="w-3 h-3 rounded-full ml-2" style="background:${this.colors[id] || CELL_MISSED}"></span>
          <span class="flex-1 text-white font-bold ml-3 truncate">${this.esc(nicknames?.[id] || "?")}</span>
          <span class="font-mono font-black text-emerald-400 text-lg">${pts}</span>
        </div>`).join("")
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
    this.tickSound?.pause()
  }

  renderCountdown(remaining, total) {
    const ratio = remaining / total
    if (remaining > 0 && remaining <= TICK_FROM) this.playTick()
    this.countdownTarget.textContent = remaining
    this.countdownTarget.style.color = ratio > 0.5 ? COLOR_GREEN : ratio > 0.25 ? COLOR_YELLOW : COLOR_RED
  }

  // ── Helpers ───────────────────────────────────────────────────────────────

  playTick() {
    this.tickSound.currentTime = 0
    this.tickSound.play().catch(() => {}) // ignore autoplay blocks
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
