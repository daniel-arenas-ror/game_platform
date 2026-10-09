import { Controller } from "@hotwired/stimulus"
import consumer from "channels/consumer"
import { t } from "controllers/shared/i18n"
import {
  fitCanvas, clearCanvas, createPen, patternHtml, ranked, esc, secondsUntil,
  restartAnimation, injectStyles, MEDALS
} from "controllers/doodle_dash/drawing"
import { confetti } from "controllers/shared/celebration"

// Countdown colour thresholds
const COLOR_GREEN  = "#4ade80"
const COLOR_YELLOW = "#facc15"
const COLOR_RED    = "#f87171"

const TICK_FROM  = 5  // seconds: a tick plays every second at the end of a drawing
const PULSE_FROM = 10 // seconds: the countdown pulses every second at the end of a drawing
const FEED_LIMIT = 7  // guesses kept in the sidebar

export default class extends Controller {
  static values  = { roomCode: String }
  static targets = [
    "turnLabel", "pattern", "canvas", "overlay", "overlayIcon", "overlayTitle", "overlayHint",
    "artistLabel", "phaseHint", "countdown", "scoreboard", "feed", "toasts",
    "phaseGameOver", "finalLeaderboard", "playAgain"
  ]

  connect() {
    this.timerHandle = null
    this.scores    = {}
    this.nicknames = {}
    this.guessed   = {}   // this turn: { pid => points }
    this.artistId  = null
    this.strokes   = []   // this turn's drawing in stroke-id order: { id, color, size, points, pen? }
    this.gone      = new Set() // ids undone this turn: late messages for them are ignored
    this.clearedUpto = 0       // ids up to this were cleared this turn
    this.offline   = new Set()
    this.tickSound = new Audio("/games/sounds/timer_count_down.mp3")
    this.dingSound = new Audio("/games/sounds/reveal.mp3")
    this.goSound   = new Audio("/games/sounds/click.mp3")

    injectStyles()
    fitCanvas(this.canvasTarget)
    this.onResize = () => { fitCanvas(this.canvasTarget); this.repaint() }
    window.addEventListener("resize", this.onResize)
    this.subscribe()
  }

  disconnect() {
    window.removeEventListener("resize", this.onResize)
    this.winSound?.pause()
    this.stopCountdown()
    this.channel?.unsubscribe()
  }

  subscribe() {
    this.channel = consumer.subscriptions.create({
      channel:   "Games::DoodleDashChannel",
      room_code: this.roomCodeValue,
      player_id: ""
    }, {
      connected: () => this.channel.perform("start_game_loop", {}),
      received:  (data) => this.handleMessage(data)
    })
  }

  handleMessage(data) {
    switch (data.action) {
      case "state_snapshot":  this.onSnapshot(data);   break
      case "choosing":        this.onChoosing(data);   break
      case "drawing":         this.onDrawing(data);    break
      case "draw":            this.onDraw(data);       break
      case "stroke_end":      this.onStrokeEnd(data);  break
      case "undo":            this.onUndo(data);       break
      case "clear":           this.onClear(data);      break
      case "hint":            this.setPattern(data.pattern, true); break
      case "guessed":         this.onGuessed(data);    break
      case "feed":            this.onFeed(data);       break
      case "turn_over":       this.onTurnOver(data);   break
      case "player_left":     this.onPlayerLeft(data); break
      case "player_presence": this.onPresence(data);   break
      case "game_over":       this.onGameOver(data);   break
      case "game_error":      this.showOverlay("⚠️", t("doodle_dash.error"), t("doodle_dash.error_hint")); break
      case "game_restarted":  window.location.reload(); break
      case "game_changed":    window.location.href = `/rooms/${this.roomCodeValue}`; break
    }
  }

  // ── Message handlers ──────────────────────────────────────────────────────

  onSnapshot({ state, nicknames }) {
    this.nicknames = nicknames || {}
    this.scores    = state.scores || {}
    this.guessed   = state.guessed || {}
    this.artistId  = state.artist_id
    this.setTurnLabel(state.turn + 1, state.total_turns)
    this.renderScoreboard()

    switch (state.status) {
      case "choosing":
        this.onChoosing({ artist_id: state.artist_id, duration: secondsUntil(state.choose_ends_at) })
        break
      case "drawing":
        this.strokes = (state.strokes || []).map(s => ({ ...s }))
        this.gone = new Set(state.removed_strokes || [])
        this.clearedUpto = state.cleared_upto || 0
        this.repaint()
        this.onDrawing({ artist_id: state.artist_id, pattern: state.pattern, turn_ends_at: state.turn_ends_at,
                         duration: state.draw_time }, false)
        break
      case "reveal":
        this.strokes = state.strokes || []
        this.repaint()
        this.onTurnOver({ word: state.word, artist_id: state.artist_id, guessed: this.guessed, scores: this.scores })
        break
      case "game_over":
        this.onGameOver({ scores: this.scores, nicknames: this.nicknames })
        break
    }
  }

  onChoosing({ artist_id, turn, total_turns, duration, nicknames }) {
    if (nicknames) this.nicknames = nicknames
    this.artistId = artist_id
    this.guessed  = {}
    this.resetDrawing()
    this.setPattern(null)
    this.clearFeed()
    if (turn) this.setTurnLabel(turn, total_turns)
    this.renderScoreboard()

    const name = this.name(artist_id)
    this.showOverlay("🤫", t("doodle_dash.picking", { name: esc(name) }), t("doodle_dash.get_phone_ready"))
    this.setSidebar(`✏️ ${name}`, t("doodle_dash.is_picking"))
    this.startCountdown(duration)
  }

  // `fresh` is false when restoring a turn after a reload: keep the strokes already drawn.
  onDrawing({ artist_id, pattern, duration, turn_ends_at }, fresh = true) {
    this.artistId = artist_id
    if (fresh) { this.resetDrawing(); this.playSound(this.goSound) }
    this.hideOverlay()
    this.setPattern(pattern)
    this.setSidebar(t("doodle_dash.is_drawing", { name: this.name(artist_id) }), t("doodle_dash.guess_on_phone"))
    this.renderScoreboard()
    this.startCountdown(turn_ends_at ? secondsUntil(turn_ends_at) : duration, duration, true)
  }

  // Live points of stroke `id`. Batches can arrive out of order; stroke_end puts it right.
  onDraw({ id, points, color, size }) {
    if (this.isGone(id)) return
    let stroke = this.strokes.find(s => s.id === id)
    if (!stroke) {
      stroke = { id, color, size, points: [], pen: createPen(this.canvasTarget, color, size) }
      this.insertStroke(stroke)
    }
    if (!stroke.pen) return // already finished
    stroke.pen.add(points)
    stroke.points.push(...points)
  }

  // The finished stroke, exactly as the artist drew it: replaces the live copy and redraws.
  onStrokeEnd({ stroke }) {
    if (this.isGone(stroke.id)) return
    this.strokes = this.strokes.filter(s => s.id !== stroke.id)
    this.insertStroke({ ...stroke })
    this.repaint()
  }

  onUndo({ id }) {
    this.gone.add(id)
    this.strokes = this.strokes.filter(s => s.id !== id)
    this.repaint()
  }

  onClear({ upto }) {
    this.clearedUpto = Math.max(this.clearedUpto, upto)
    this.strokes = this.strokes.filter(s => s.id > upto)
    this.repaint()
  }

  // Redraws everything: finished strokes whole, live ones with a fresh pen that carries on.
  repaint() {
    clearCanvas(this.canvasTarget)
    this.strokes.forEach(s => {
      const pen = createPen(this.canvasTarget, s.color, s.size)
      pen.add(s.points)
      if (s.pen) s.pen = pen
      else pen.end()
    })
  }

  isGone(id) {
    return id <= this.clearedUpto || this.gone.has(id)
  }

  insertStroke(stroke) {
    const at = this.strokes.findIndex(s => s.id > stroke.id)
    if (at === -1) this.strokes.push(stroke)
    else this.strokes.splice(at, 0, stroke)
  }

  onGuessed({ player_id, points, scores }) {
    this.guessed[player_id] = points
    if (scores) this.scores = scores
    this.renderScoreboard()
    this.addFeed(`<span class="text-lime-400 font-black">${t("doodle_dash.guessed_it", { name: esc(this.name(player_id)) })}</span>`)
    this.toast(`${t("doodle_dash.guessed_toast", { name: esc(this.name(player_id)) })} <span class="font-mono">+${points}</span>`)
    this.playSound(this.dingSound)
    restartAnimation(this.scoreboardTarget.querySelector(`[data-score="${player_id}"]`), "dd-pop")
  }

  onFeed({ player_id, kind, text }) {
    const who = `<span class="font-bold text-slate-300">${esc(this.name(player_id))}</span>`
    if (kind === "close") this.addFeed(`${who} <span class="text-yellow-300 font-bold">${t("doodle_dash.is_close")}</span>`)
    else this.addFeed(`${who} <span class="text-slate-400">${esc(text)}</span>`)
  }

  onTurnOver({ word, artist_id, guessed, scores, turn, total_turns, nicknames }) {
    this.stopCountdown()
    this.toastsTarget.innerHTML = "" // the reveal banner sits where the toasts are
    this.countdownTarget.textContent = ""
    if (nicknames) this.nicknames = nicknames
    if (scores) this.scores = scores
    this.guessed = guessed || {}
    this.patternTarget.innerHTML = patternHtml(word ? word.split("") : null, true, true)
    this.renderScoreboard()

    const count = Object.keys(this.guessed).length
    const hint  = count === 0 ? t("doodle_dash.nobody_got_it") :
                  t("doodle_dash.players_guessed", { count, artist: esc(this.name(artist_id)), points: count * 25 })
    const guessers = Object.keys(this.scores).filter(id => id !== artist_id).length
    this.showOverlay("💡", t("doodle_dash.it_was", { word: esc(word || "?") }), hint, true, true)
    this.setSidebar(count && count >= guessers ? t("doodle_dash.everyone_got_it") : t("doodle_dash.times_up"),
                    turn && turn < total_turns ? t("doodle_dash.next_artist") : t("doodle_dash.final_results"))
  }

  onPlayerLeft({ player_id }) {
    delete this.scores[player_id]
    delete this.guessed[player_id]
    this.offline.delete(player_id)
    this.renderScoreboard()
  }

  onPresence({ player_id, connected }) {
    if (connected) this.offline.delete(player_id)
    else this.offline.add(player_id)
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
    confetti(80)
  }

  // ── Canvas + word ─────────────────────────────────────────────────────────

  resetDrawing() {
    this.strokes = []
    this.gone = new Set()
    this.clearedUpto = 0
    clearCanvas(this.canvasTarget)
  }

  setPattern(pattern, animate = false) {
    this.patternTarget.innerHTML = patternHtml(pattern)
    if (animate) restartAnimation(this.patternTarget, "dd-pop")
  }

  // `reveal`: a banner along the bottom, so the finished drawing stays visible above it.
  showOverlay(icon, title, hint, animate = true, reveal = false) {
    this.overlayIconTarget.textContent = icon
    this.overlayTitleTarget.innerHTML  = title
    this.overlayHintTarget.innerHTML   = hint
    this.overlayTarget.classList.remove("hidden")
    this.overlayTarget.classList.toggle("bg-slate-950/90", !reveal)
    this.overlayTarget.classList.toggle("justify-center", !reveal)
    ;[ "justify-end", "pb-8", "bg-gradient-to-t", "from-slate-950", "via-slate-950/85", "via-35%", "to-transparent", "to-60%" ]
      .forEach(c => this.overlayTarget.classList.toggle(c, reveal))
    if (animate) restartAnimation(this.overlayTitleTarget, "dd-pop")
  }

  hideOverlay() {
    this.overlayTarget.classList.add("hidden")
  }

  // ── Sidebar ───────────────────────────────────────────────────────────────

  setSidebar(title, hint = "") {
    if (this.artistLabelTarget.textContent !== title) restartAnimation(this.artistLabelTarget, "dd-slide")
    this.artistLabelTarget.textContent = title
    this.phaseHintTarget.textContent   = hint
  }

  setTurnLabel(turn, total) {
    this.turnLabelTarget.textContent = turn > 0 && total ? t("doodle_dash.turn", { turn, total }) : ""
  }

  addFeed(html) {
    const li = document.createElement("li")
    li.className = "dd-slide truncate"
    li.innerHTML = html
    this.feedTarget.prepend(li)
    while (this.feedTarget.children.length > FEED_LIMIT) this.feedTarget.lastElementChild.remove()
  }

  clearFeed() {
    this.feedTarget.innerHTML = ""
  }

  toast(html) {
    const el = document.createElement("div")
    el.className = "dd-slide bg-lime-400 text-slate-950 font-black text-xl px-6 py-3 rounded-2xl shadow-2xl"
    el.innerHTML = html
    this.toastsTarget.appendChild(el)
    setTimeout(() => el.remove(), 2500)
  }

  renderScoreboard() {
    this.scoreboardTarget.innerHTML = ranked(this.scores).map(({ id, pts }) => {
      const mark = id === this.artistId ? "✏️ " : id in this.guessed ? "✅ " : ""
      const away = this.offline.has(id)
      return `
        <div class="flex items-center gap-2 ${away ? "opacity-40" : ""}" ${away ? `title="${t("doodle_dash.offline")}"` : ""}>
          <span class="flex-1 font-bold truncate">${mark}${esc(this.name(id))}</span>
          <span data-score="${id}" class="inline-block font-mono font-black text-lime-400 w-14 text-right">${pts}</span>
        </div>`
    }).join("")
  }

  buildLeaderboard(scores, nicknames) {
    return ranked(scores).map(({ id, pts, place }) => `
      <div class="flex items-center justify-between bg-slate-800 rounded-xl px-5 py-3">
        <span class="text-2xl w-8">${MEDALS[place] || `#${place}`}</span>
        <span class="flex-1 text-white font-bold ml-3 truncate">${esc(nicknames?.[id] || "?")}</span>
        <span class="font-mono font-black text-lime-400 text-lg">${pts}</span>
      </div>`).join("")
  }

  name(id) {
    return this.nicknames[id] || t("doodle_dash.someone")
  }

  // ── Countdown ─────────────────────────────────────────────────────────────

  startCountdown(seconds, total = seconds, ticks = false) {
    this.stopCountdown()
    let remaining = seconds
    this.renderCountdown(remaining, total, ticks)

    this.timerHandle = setInterval(() => {
      remaining -= 1
      this.renderCountdown(Math.max(remaining, 0), total, ticks)
      if (remaining <= 0) this.stopCountdown()
    }, 1000)
  }

  stopCountdown() {
    clearInterval(this.timerHandle)
    this.timerHandle = null
    this.tickSound?.pause()
  }

  renderCountdown(remaining, total, ticks) {
    const ratio = total ? remaining / total : 0
    if (ticks && remaining > 0 && remaining <= TICK_FROM) this.playSound(this.tickSound)
    if (ticks && remaining > 0 && remaining <= PULSE_FROM) restartAnimation(this.countdownTarget, "dd-pulse")
    this.countdownTarget.textContent = remaining
    this.countdownTarget.style.color = ratio > 0.5 ? COLOR_GREEN : ratio > 0.25 ? COLOR_YELLOW : COLOR_RED
  }

  playSound(audio) {
    audio.currentTime = 0
    audio.play().catch(() => {}) // ignore autoplay blocks
  }
}
