import { Controller } from "@hotwired/stimulus"
import consumer from "channels/consumer"
import { buildBoard, cardAt, showBack, showFace, ranked, esc, MEDALS } from "controllers/matching_pairs/cards"

// Countdown colour thresholds
const COLOR_GREEN  = "#4ade80"
const COLOR_YELLOW = "#facc15"
const COLOR_RED    = "#f87171"

// Tick sound plays once per second during the last seconds of a phase
const TICK_FROM = 5

export default class extends Controller {
  static values  = { roomCode: String }
  static targets = [
    "board", "roundLabel", "phaseTitle", "phaseHint", "countdown",
    "scoreboard", "pairsLabel",
    "phaseGameOver", "finalLeaderboard", "playAgain"
  ]

  connect() {
    this.timerHandle = null
    this.cols      = 0
    this.rows      = 0
    this.pairs     = 0
    this.scores    = {}
    this.progress  = {} // { pid => { matches, wrong } } for the current round
    this.nicknames = {}
    this.tickSound = new Audio("/games/sounds/timer_count_down.mp3")
    this.subscribe()
  }

  disconnect() {
    this.winSound?.pause()
    this.stopCountdown()
    this.channel?.unsubscribe()
  }

  subscribe() {
    this.channel = consumer.subscriptions.create({
      channel:   "Games::MatchingPairsChannel",
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
      case "memorize_board":  this.onMemorize(data);    break
      case "play":            this.onPlay(data);        break
      case "progress":        this.onProgress(data);    break
      case "round_over":      this.onRoundOver(data);   break
      case "player_left":     this.onPlayerLeft(data);  break
      case "game_over":       this.onGameOver(data);    break
      case "game_error":      this.setPhase("Something went wrong", "Start a new game"); break
      case "game_restarted":  window.location.reload(); break
      case "game_changed":    window.location.href = `/rooms/${this.roomCodeValue}`; break
    }
  }

  // ── Message handlers ──────────────────────────────────────────────────────

  onSnapshot({ state, nicknames }) {
    this.nicknames = nicknames || {}
    this.scores    = state.scores || {}
    this.progress  = state.progress || {}
    this.setBoardSize(state.cols, state.rows)
    this.setRoundLabel(state.round, state.total_rounds)
    this.renderScoreboard()

    const remaining = (endsAt) => Math.max(Math.round(endsAt - Date.now() / 1000), 0)

    switch (state.status) {
      case "memorize":
        this.revealAll(state.deck)
        this.setPhase("Memorize the board!", "Phones are covered until the cards turn over.")
        break
      case "playing":
        this.setPhase("Find the pairs!", "Everyone is playing on their phone.")
        this.startCountdown(remaining(state.round_ends_at), state.round_time)
        break
      case "round_over":
        this.revealAll(state.deck)
        this.setPhase("Round over", "Next board coming up…")
        break
      case "game_over":
        this.revealAll(state.deck)
        this.onGameOver({ scores: this.scores, nicknames: this.nicknames })
        break
      default:
        this.setPhase("Get ready…", "Look at this screen — the board shows up here first.")
    }
  }

  onMemorize({ round, total_rounds, cols, rows, duration, deck }) {
    this.setBoardSize(cols, rows)
    this.setRoundLabel(round, total_rounds)
    Object.keys(this.scores).forEach(id => { this.progress[id] = { matches: 0, wrong: 0 } })
    this.renderScoreboard()

    this.revealAll(deck)
    this.setPhase("Memorize the board!", "Remember where every card is — then find the pairs on your phone.")
    this.startCountdown(duration)
  }

  onPlay({ duration }) {
    this.hideAll()
    this.setPhase("Find the pairs!", `+100 per pair · −10 per wrong pair`)
    this.startCountdown(duration)
  }

  onProgress({ player_id, score, matches, cleared }) {
    this.scores[player_id] = score
    this.progress[player_id] = { ...(this.progress[player_id] || {}), matches, cleared }
    this.renderScoreboard()
  }

  onRoundOver({ round, total_rounds, deck, scores, progress, nicknames }) {
    this.stopCountdown()
    this.scores    = scores || this.scores
    this.progress  = progress || this.progress
    this.nicknames = nicknames || this.nicknames
    this.revealAll(deck)
    this.renderScoreboard()
    this.countdownTarget.textContent = ""
    this.setPhase(`Round ${round} over`, round < total_rounds ? "Next board coming up…" : "Final results…")
  }

  onPlayerLeft({ player_id }) {
    delete this.scores[player_id]
    delete this.progress[player_id]
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

  // ── Board ─────────────────────────────────────────────────────────────────

  setBoardSize(cols, rows) {
    if (!cols || !rows) return
    this.pairs = cols * rows / 2
    this.pairsLabelTarget.textContent = `${this.pairs} pairs`
    if (cols === this.cols && rows === this.rows) return

    this.cols = cols
    this.rows = rows
    const width = `min(56vw, calc(76vh * ${cols} / ${rows}))`
    this.boardTarget.style.width = width
    buildBoard(this.boardTarget, cols, rows, `calc(${width} / ${cols} * 0.45)`)
  }

  revealAll(deck) {
    (deck || []).forEach((item, i) => {
      const card = cardAt(this.boardTarget, i)
      if (card) showFace(card, item)
    })
  }

  hideAll() {
    this.boardTarget.querySelectorAll("[data-index]").forEach(card => showBack(card))
  }

  // ── Sidebar ───────────────────────────────────────────────────────────────

  setPhase(title, hint = "") {
    this.phaseTitleTarget.textContent = title
    this.phaseHintTarget.textContent  = hint
  }

  setRoundLabel(round, total) {
    this.roundLabelTarget.textContent = round ? `Round ${round} / ${total}` : ""
  }

  renderScoreboard() {
    this.scoreboardTarget.innerHTML = ranked(this.scores).map(({ id, pts }) => {
      const matches = this.progress[id]?.matches || 0
      const pct     = this.pairs ? Math.round(matches / this.pairs * 100) : 0
      const done    = this.pairs && matches >= this.pairs
      return `
        <div>
          <div class="flex items-center gap-2">
            <span class="flex-1 font-bold truncate">${done ? "✅ " : ""}${esc(this.nicknames[id] || "?")}</span>
            <span class="text-slate-500 text-xs font-mono">${matches}/${this.pairs}</span>
            <span class="font-mono font-black text-rose-400 w-14 text-right">${pts}</span>
          </div>
          <div class="h-1.5 bg-slate-700 rounded-full mt-1 overflow-hidden">
            <div class="h-full bg-rose-500 rounded-full transition-all duration-300" style="width:${pct}%"></div>
          </div>
        </div>`
    }).join("")
  }

  buildLeaderboard(scores, nicknames) {
    return ranked(scores).map(({ id, pts, place }) => `
      <div class="flex items-center justify-between bg-slate-800 rounded-xl px-5 py-3">
        <span class="text-2xl w-8">${MEDALS[place] || `#${place}`}</span>
        <span class="flex-1 text-white font-bold ml-3 truncate">${esc(nicknames?.[id] || "?")}</span>
        <span class="font-mono font-black text-rose-400 text-lg">${pts}</span>
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

  playTick() {
    this.tickSound.currentTime = 0
    this.tickSound.play().catch(() => {}) // ignore autoplay blocks
  }
}
