import { Controller } from "@hotwired/stimulus"
import consumer from "channels/consumer"
import {
  PALETTE, ERASER, BRUSH_SIZES, fitCanvas, clearCanvas, drawPoints, redraw, patternHtml, ranked, esc,
  secondsUntil, restartAnimation, injectStyles, MEDALS
} from "controllers/doodle_dash/drawing"
import { celebrateWin, isTopScore, pop } from "controllers/shared/celebration"

// Countdown colour thresholds
const COLOR_GREEN  = "#4ade80"
const COLOR_YELLOW = "#facc15"
const COLOR_RED    = "#f87171"

const SEND_EVERY   = 50     // ms between two batches of points while drawing
const BATCH_LIMIT  = 100    // points: send early when a batch gets this big (server max is 120)
const MIN_STEP     = 0.002  // canvas fractions: smaller moves are skipped

const SYNC_AFTER   = 1000   // ms: the artist asks again for their words if they haven't arrived

const PANELS = [ "panelWaiting", "panelChoose", "panelDraw", "panelGuess", "panelReveal" ]

export default class extends Controller {
  static values  = { roomCode: String, playerId: String }
  static targets = [
    "score", "status", "countdown",
    ...PANELS, "waitingTitle", "waitingHint",
    "choices", "word", "canvas", "colors", "sizes",
    "pattern", "guessForm", "guessInput", "feedback",
    "revealWord", "revealPoints",
    "phaseGameOver", "gameOverIcon", "gameOverTitle", "finalScore"
  ]

  connect() {
    this.timerHandle = null
    this.nicknames   = {}
    this.artistId    = null
    this.word        = null
    this.hasGuessed  = false
    this.color       = PALETTE[0]
    this.size        = BRUSH_SIZES[1]
    this.strokes     = []   // the artist's own drawing this turn, to redraw after undo or a resize
    this.pointerId   = null // the finger that is drawing; other fingers are ignored
    this.dingSound   = new Audio("/games/sounds/reveal.mp3")

    injectStyles()
    this.renderTools()
    this.onResize = () => {
      if (this.panelDrawTarget.classList.contains("hidden")) return
      fitCanvas(this.canvasTarget)
      redraw(this.canvasTarget, this.strokes)
    }
    window.addEventListener("resize", this.onResize)
    this.subscribe()
  }

  disconnect() {
    window.removeEventListener("resize", this.onResize)
    clearInterval(this.timerHandle)
    clearInterval(this.flushHandle)
    clearTimeout(this.syncHandle)
    this.channel?.unsubscribe()
  }

  subscribe() {
    this.channel = consumer.subscriptions.create({
      channel:   "Games::DoodleDashChannel",
      room_code: this.roomCodeValue,
      player_id: this.playerIdValue
    }, {
      received: (data) => this.handleMessage(data)
    })
  }

  handleMessage(data) {
    switch (data.action) {
      case "state_snapshot":  this.onSnapshot(data);    break
      case "choosing":        this.onChoosing(data);    break
      case "choose_word":     this.onChooseWord(data);  break
      case "your_word":       this.onYourWord(data);    break
      case "drawing":         this.onDrawing(data);     break
      case "hint":            this.setPattern(data.pattern, true); break
      case "guess_result":    this.onGuessResult(data); break
      case "guessed":         this.onGuessed(data);     break
      case "turn_over":       this.onTurnOver(data);    break
      case "game_over":       this.onGameOver(data);    break
      case "game_restarted":  window.location.reload(); break
      case "game_changed":    window.location.href = `/rooms/${this.roomCodeValue}`; break
    }
  }

  get isArtist() {
    return this.artistId === this.playerIdValue
  }

  // ── Message handlers ──────────────────────────────────────────────────────

  onSnapshot({ state, nicknames }) {
    this.nicknames = nicknames || {}
    this.artistId  = state.artist_id
    this.setScore(state.scores?.[this.playerIdValue] ?? 0)

    switch (state.status) {
      case "choosing":
        this.onChoosing({ artist_id: state.artist_id, duration: secondsUntil(state.choose_ends_at) })
        if (state.choices) this.onChooseWord({ choices: state.choices })
        break
      case "drawing":
        this.hasGuessed = this.playerIdValue in (state.guessed || {})
        if (this.isArtist && state.word) this.word = state.word
        this.onDrawing({ artist_id: state.artist_id, pattern: state.pattern, turn_ends_at: state.turn_ends_at,
                         duration: state.draw_time })
        break
      case "reveal":
        this.onTurnOver({ word: state.word, guessed: state.guessed, scores: state.scores, artist_id: state.artist_id })
        break
      case "game_over":
        this.onGameOver({ scores: state.scores })
        break
    }
  }

  onChoosing({ artist_id, turn, total_turns, duration, nicknames }) {
    if (nicknames) this.nicknames = nicknames
    this.artistId   = artist_id
    this.word       = null
    this.hasGuessed = false
    this.strokes    = []
    this.setStatus(turn ? `Turn ${turn}/${total_turns}` : "")
    this.startCountdown(duration)

    if (this.isArtist) {
      this.hasChoices = false
      this.choicesTarget.innerHTML = `<p class="text-center text-slate-500">Getting your words…</p>`
      this.showPanel("panelChoose")
      // The words travel on this phone's private stream and can arrive before this announcement.
      if (this.earlyChoices) this.onChooseWord({ choices: this.earlyChoices })
      this.syncUnless(() => this.hasChoices)
      navigator.vibrate?.([ 80, 60, 80 ])
    } else {
      this.showWaiting(`${this.name(artist_id)} is picking a word…`, "Get ready to guess! Watch the TV.")
    }
  }

  onChooseWord({ choices }) {
    if (!this.isArtist) { this.earlyChoices = choices; return }
    if (this.hasChoices) return
    this.hasChoices   = true
    this.earlyChoices = null
    this.choicesTarget.innerHTML = choices.map((word, i) => `
      <button type="button" data-index="${i}"
              class="dd-slide w-full py-5 rounded-2xl bg-slate-800 border-2 border-slate-700 active:border-lime-400
                     text-2xl font-black capitalize cursor-pointer active:scale-[0.98] transition-transform"
              style="animation-delay:${i * 60}ms">${esc(word)}</button>`).join("")
    this.choicesTarget.querySelectorAll("button").forEach(btn => {
      btn.addEventListener("click", () => {
        this.choicesTarget.querySelectorAll("button").forEach(b => { b.disabled = true })
        btn.classList.add("border-lime-400", "bg-lime-500/10")
        this.channel.perform("choose_word", { index: Number(btn.dataset.index) })
      }, { once: true })
    })
  }

  onYourWord({ word }) {
    this.word = word
    this.wordTarget.textContent = word
  }

  onDrawing({ artist_id, pattern, duration, turn_ends_at }) {
    this.artistId = artist_id
    const seconds = turn_ends_at ? secondsUntil(turn_ends_at) : duration
    this.startCountdown(seconds, duration)

    if (this.isArtist) {
      this.wordTarget.textContent = this.word || "…"
      this.syncUnless(() => this.word)
      this.setStatus("You're drawing!")
      this.showPanel("panelDraw")
      fitCanvas(this.canvasTarget)
      redraw(this.canvasTarget, this.strokes)
    } else {
      this.setStatus(`${this.name(artist_id)} is drawing`)
      this.setPattern(pattern)
      this.showPanel("panelGuess")
      this.setGuessing(!this.hasGuessed)
      if (this.hasGuessed) this.setFeedback("You got it! Wait for the others.", COLOR_GREEN)
      else { this.setFeedback(""); this.guessInputTarget.focus() }
    }
  }

  onGuessResult({ result, points }) {
    if (result === "correct") {
      this.hasGuessed = true
      this.setGuessing(false)
      this.setFeedback(`You got it! +${points}`, COLOR_GREEN)
      this.playSound(this.dingSound)
      navigator.vibrate?.([ 60, 40, 120 ])
    } else if (result === "close") {
      this.setFeedback("So close!", COLOR_YELLOW, "dd-shake")
      navigator.vibrate?.(60)
    } else {
      this.setFeedback("Not it. Keep trying!", "#94a3b8", "dd-shake")
    }
  }

  onGuessed({ player_id, scores }) {
    if (scores?.[this.playerIdValue] !== undefined) this.setScore(scores[this.playerIdValue])
    if (this.isArtist) {
      this.setStatus(`🎉 ${this.name(player_id)} guessed it!`)
      navigator.vibrate?.(40)
    }
  }

  onTurnOver({ word, guessed, scores, artist_id }) {
    this.stopCountdown()
    this.countdownTarget.textContent = ""
    this.endStroke()
    if (scores?.[this.playerIdValue] !== undefined) this.setScore(scores[this.playerIdValue])

    const count = Object.keys(guessed || {}).length
    let points
    if (artist_id === this.playerIdValue) points = count ? `+${count * 25} for your drawing` : "Nobody got it this time"
    else if (guessed?.[this.playerIdValue]) points = `You got it! +${guessed[this.playerIdValue]}`
    else points = "You didn't get this one"

    this.revealWordTarget.textContent = word || "?"
    this.revealPointsTarget.textContent = points
    const guessers = Object.keys(scores || {}).filter(id => id !== artist_id).length
    this.setStatus(count && count >= guessers ? "Everyone got it!" : "Time's up!")
    this.showPanel("panelReveal")
    restartAnimation(this.revealWordTarget, "dd-pop")
  }

  onGameOver({ scores }) {
    this.stopCountdown()
    const me    = ranked(scores).find(r => r.id === this.playerIdValue)
    const place = me?.place
    const tied  = me && ranked(scores).filter(r => r.place === place).length > 1

    this.gameOverIconTarget.textContent  = MEDALS[place] || "🏁"
    this.gameOverTitleTarget.textContent = !me ? "Game over" :
      place === 1 ? (tied ? "Tied for 1st!" : "You won!") :
      `${tied ? "Tied for" : "You finished"} #${place}`
    this.finalScoreTarget.textContent = me?.pts ?? 0
    this.phaseGameOverTarget.classList.remove("hidden")
    if (isTopScore(scores, this.playerIdValue)) celebrateWin(this.gameOverTitleTarget)
    else pop(this.gameOverIconTarget)
  }

  // ── Drawing (artist) ──────────────────────────────────────────────────────

  penDown(event) {
    if (!this.isArtist || this.pointerId !== null) return
    event.preventDefault()
    this.canvasTarget.setPointerCapture(event.pointerId)
    this.pointerId = event.pointerId

    const point = this.pointFrom(event)
    this.stroke = { color: this.color, size: this.size, points: [ point ] }
    this.last   = drawPoints(this.canvasTarget, [ point ], this.color, this.size)
    this.buffer = [ point ]
    this.startPending = true
    this.flushHandle  = setInterval(() => this.flush(), SEND_EVERY)
  }

  penMove(event) {
    if (event.pointerId !== this.pointerId) return
    event.preventDefault()
    const events = event.getCoalescedEvents?.() || [ event ]

    events.forEach(e => {
      const point = this.pointFrom(e)
      if (Math.hypot(point[0] - this.last[0], point[1] - this.last[1]) < MIN_STEP) return
      this.last = drawPoints(this.canvasTarget, [ point ], this.color, this.size, this.last)
      this.stroke.points.push(point)
      this.buffer.push(point)
    })
    if (this.buffer.length >= BATCH_LIMIT) this.flush()
  }

  penUp(event) {
    if (event.pointerId !== this.pointerId) return
    this.endStroke()
  }

  endStroke() {
    if (this.pointerId === null) return
    this.flush()
    clearInterval(this.flushHandle)
    this.channel.perform("stroke_end", {})
    this.strokes.push(this.stroke)
    this.pointerId = null
    this.stroke = null
  }

  flush() {
    if (!this.buffer?.length) return
    this.channel.perform("draw", { points: this.buffer, color: this.stroke.color, size: this.stroke.size, start: this.startPending })
    this.startPending = false
    this.buffer = []
  }

  // The pointer position as fractions of the canvas, rounded like the server keeps them.
  pointFrom(event) {
    const rect  = this.canvasTarget.getBoundingClientRect()
    const clamp = v => Math.round(Math.min(Math.max(v, 0), 1) * 10000) / 10000
    return [ clamp((event.clientX - rect.left) / rect.width), clamp((event.clientY - rect.top) / rect.height) ]
  }

  undo() {
    if (!this.isArtist || !this.strokes.length) return
    this.strokes.pop()
    redraw(this.canvasTarget, this.strokes)
    this.channel.perform("undo", {})
  }

  clear() {
    if (!this.isArtist || !this.strokes.length) return
    this.strokes = []
    clearCanvas(this.canvasTarget)
    this.channel.perform("clear", {})
  }

  // ── Tools ─────────────────────────────────────────────────────────────────

  renderTools() {
    this.colorsTarget.innerHTML = PALETTE.map(color => `
      <button type="button" data-color="${color}" aria-label="${color === ERASER ? "Eraser" : `Color ${color}`}"
              class="size-10 rounded-full border-2 border-slate-600 cursor-pointer grid place-items-center text-lg"
              style="background:${color}">${color === ERASER ? "🧽" : ""}</button>`).join("")
    this.sizesTarget.innerHTML = BRUSH_SIZES.map(size => `
      <button type="button" data-size="${size}" aria-label="Brush size ${size}"
              class="size-12 rounded-xl bg-slate-800 border-2 border-slate-700 cursor-pointer grid place-items-center">
        <span class="block rounded-full bg-white" style="width:${4 + size * 0.8}px;height:${4 + size * 0.8}px"></span>
      </button>`).join("")

    this.colorsTarget.addEventListener("click", (e) => {
      const btn = e.target.closest("[data-color]")
      if (btn) { this.color = btn.dataset.color; this.markTools() }
    })
    this.sizesTarget.addEventListener("click", (e) => {
      const btn = e.target.closest("[data-size]")
      if (btn) { this.size = Number(btn.dataset.size); this.markTools() }
    })
    this.markTools()
  }

  markTools() {
    this.colorsTarget.querySelectorAll("[data-color]").forEach(btn => {
      const on = btn.dataset.color === this.color
      btn.classList.toggle("ring-4", on)
      btn.classList.toggle("ring-lime-400", on)
      btn.setAttribute("aria-pressed", on)
    })
    this.sizesTarget.querySelectorAll("[data-size]").forEach(btn => {
      const on = Number(btn.dataset.size) === this.size
      btn.classList.toggle("border-lime-400", on)
      btn.classList.toggle("bg-lime-500/10", on)
      btn.classList.toggle("border-slate-700", !on)
      btn.setAttribute("aria-pressed", on)
    })
  }

  // ── Guessing ──────────────────────────────────────────────────────────────

  sendGuess(event) {
    event.preventDefault()
    const text = this.guessInputTarget.value.trim()
    if (!text || this.hasGuessed) return
    this.channel.perform("guess", { text })
    this.guessInputTarget.value = ""
    this.guessInputTarget.focus()
  }

  setGuessing(on) {
    this.guessInputTarget.disabled = !on
    this.guessFormTarget.querySelector("button").disabled = !on
    this.guessFormTarget.classList.toggle("opacity-40", !on)
  }

  setPattern(pattern, animate = false) {
    this.patternTarget.innerHTML = patternHtml(pattern, false)
    if (animate) restartAnimation(this.patternTarget, "dd-pop")
  }

  setFeedback(text, color = "#fff", animation = "dd-pop") {
    this.feedbackTarget.textContent = text
    this.feedbackTarget.style.color = color
    if (text) restartAnimation(this.feedbackTarget, animation)
  }

  // Asks the server for this phone's state again unless `received()` turns true in time.
  syncUnless(received) {
    clearTimeout(this.syncHandle)
    this.syncHandle = setTimeout(() => { if (!received()) this.channel.perform("sync", {}) }, SYNC_AFTER)
  }

  // ── UI helpers ────────────────────────────────────────────────────────────

  showPanel(name) {
    PANELS.forEach(p => this[`${p}Target`].classList.toggle("hidden", p !== name))
  }

  showWaiting(title, hint) {
    this.waitingTitleTarget.textContent = title
    this.waitingHintTarget.textContent  = hint
    this.showPanel("panelWaiting")
  }

  setScore(score) {
    this.scoreTarget.textContent = score
  }

  setStatus(text) {
    this.statusTarget.textContent = text
  }

  name(id) {
    return this.nicknames[id] || "Someone"
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
    const ratio = total ? remaining / total : 0
    this.countdownTarget.textContent = remaining
    this.countdownTarget.style.color = ratio > 0.5 ? COLOR_GREEN : ratio > 0.25 ? COLOR_YELLOW : COLOR_RED
  }

  playSound(audio) {
    audio.currentTime = 0
    audio.play().catch(() => {}) // ignore autoplay blocks
  }
}
