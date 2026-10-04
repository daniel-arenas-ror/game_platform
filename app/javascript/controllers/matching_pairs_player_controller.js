import { Controller } from "@hotwired/stimulus"
import consumer from "channels/consumer"
import {
  buildBoard, cardAt, showBack, showFace, preload, ranked, restartAnimation, injectStyles, FLIP_MS, MEDALS
} from "controllers/matching_pairs/cards"
import { celebrateWin, confetti, pop } from "controllers/shared/celebration"

// Countdown colour thresholds
const COLOR_GREEN  = "#4ade80"
const COLOR_YELLOW = "#facc15"
const COLOR_RED    = "#f87171"

// How long a wrong pair stays face up (after the flip) before both cards turn back
const MISS_DELAY = 500

export default class extends Controller {
  static values  = { roomCode: String, playerId: String }
  static targets = [
    "board", "cover", "coverTitle", "coverHint",
    "score", "pairs", "status", "countdown", "feedback",
    "phaseGameOver", "gameOverIcon", "gameOverTitle", "finalScore"
  ]

  connect() {
    this.timerHandle = null
    this.missHandle  = null
    this.cols      = 0
    this.rows      = 0
    this.pairs     = 0
    this.matches   = 0
    this.items     = {}    // index => card item, for every card this player has seen face up
    this.openIndex = null  // first card of the pair being tried
    this.active    = false // the round is being played
    this.pending   = false // a flip is waiting for the server's answer
    this.resolving = false // a wrong pair is showing before it turns back
    this.flipSound   = new Audio("/games/sounds/flip.mp3")
    this.revealSound = new Audio("/games/sounds/reveal.mp3")
    injectStyles()
    this.subscribe()
  }

  disconnect() {
    this.channel?.unsubscribe()
    clearInterval(this.timerHandle)
    clearTimeout(this.missHandle)
    this.revealSound.pause()
  }

  subscribe() {
    this.channel = consumer.subscriptions.create({
      channel:   "Games::MatchingPairsChannel",
      room_code: this.roomCodeValue,
      player_id: this.playerIdValue
    }, {
      received: (data) => this.handleMessage(data)
    })
  }

  handleMessage(data) {
    switch (data.action) {
      case "state_snapshot":  this.onSnapshot(data);    break
      case "memorize":        this.onMemorize(data);    break
      case "play":            this.onPlay(data);        break
      case "flip_result":     this.onFlipResult(data);  break
      case "flip_rejected":   this.pending = false;     break
      case "round_over":      this.onRoundOver(data);   break
      case "game_over":       this.onGameOver(data);    break
      case "game_restarted":  window.location.reload(); break
      case "game_changed":    window.location.href = `/rooms/${this.roomCodeValue}`; break
    }
  }

  // ── Message handlers ──────────────────────────────────────────────────────

  onSnapshot({ state, board }) {
    this.setScore(state.scores?.[this.playerIdValue] ?? 0)
    this.newBoard(state.cols, state.rows)

    const remaining = (endsAt) => Math.max(Math.round(endsAt - Date.now() / 1000), 0)

    switch (state.status) {
      case "memorize":
        preload(state.preload)
        this.showCover("Look at the TV!", "Remember where every card is.")
        this.setStatus(`Round ${state.round}/${state.total_rounds} · Memorize`)
        this.startCountdown(remaining(state.memorize_ends_at), state.memorize_time)
        break
      case "playing":
        preload(state.preload)
        this.restoreBoard(board)
        this.startPlaying(remaining(state.round_ends_at), state.round_time)
        break
      case "round_over":
        this.restoreBoard(board)
        this.onRoundOver(state)
        break
      case "game_over":
        this.onGameOver({ scores: state.scores })
        break
    }
  }

  onMemorize({ round, total_rounds, cols, rows, duration, preload: urls }) {
    preload(urls)
    this.newBoard(cols, rows, true)
    this.setFeedback("")
    this.showCover("Look at the TV!", "Remember where every card is.")
    this.setStatus(`Round ${round}/${total_rounds} · Memorize`)
    this.startCountdown(duration)
  }

  onPlay({ duration }) {
    this.startPlaying(duration)
  }

  onFlipResult({ result, index, item, other, score, matches, cleared }) {
    this.pending = false
    const card = cardAt(this.boardTarget, index)
    if (!card) return
    this.items[index] = item

    if (result === "open") {
      this.openIndex = index
      showFace(card, item)
      return
    }

    const otherCard = cardAt(this.boardTarget, other)
    this.openIndex = null
    this.setScore(score)

    if (result === "match") {
      showFace(card, item, "matched")
      showFace(otherCard, this.items[other], "matched")
      ;[ card, otherCard ].forEach(c => restartAnimation(c, "mp-pulse"))
      this.setMatches(matches)
      this.playSound(this.revealSound)
      this.vibrate(60)
      if (cleared) {
        this.active = false
        this.setFeedback("🎉 Board cleared!", COLOR_GREEN)
        this.setStatus("All pairs found — wait for the others")
        setTimeout(() => { confetti(); this.vibrate([ 60, 40, 60, 40, 160 ]) }, FLIP_MS)
      } else {
        this.setFeedback("+100", COLOR_GREEN)
      }
      return
    }

    // A miss: both cards stay up briefly, then turn back.
    showFace(card, item, "miss")
    showFace(otherCard, this.items[other], "miss")
    ;[ card, otherCard ].forEach(c => restartAnimation(c, "mp-shake"))
    this.setFeedback("−10", COLOR_RED)
    this.vibrate(120)
    this.resolving = true
    this.missHandle = setTimeout(() => {
      [ card, otherCard ].forEach(c => { if (c.dataset.state === "miss") showBack(c) })
      this.resolving = false
    }, FLIP_MS + MISS_DELAY)
  }

  onRoundOver({ deck, scores, round, total_rounds }) {
    this.active = false
    this.stopCountdown()
    this.countdownTarget.textContent = ""
    this.hideCover()
    this.setScore(scores?.[this.playerIdValue] ?? this.scoreTarget.textContent)

    // Show the whole board; the pairs this player missed are dimmed.
    clearTimeout(this.missHandle)
    this.resolving = false
    ;(deck || []).forEach((item, i) => {
      const card = cardAt(this.boardTarget, i)
      if (!card || card.dataset.state === "matched") return
      setTimeout(() => { showFace(card, item); card.classList.add("mp-dim") }, i * 25)
    })

    this.setStatus(round < total_rounds ? "Round over · next board soon" : "Round over")
    this.setFeedback(`You found ${this.matches}/${this.pairs} pairs`, "#fff")
  }

  onGameOver({ scores }) {
    this.active = false
    this.stopCountdown()
    const me     = ranked(scores).find(r => r.id === this.playerIdValue)
    const place  = me?.place
    const tied   = me && ranked(scores).filter(r => r.place === place).length > 1

    this.gameOverIconTarget.textContent  = MEDALS[place] || "🏁"
    this.gameOverTitleTarget.textContent = !me ? "Game over" :
      place === 1 ? (tied ? "Tied for 1st!" : "You won!") :
      `${tied ? "Tied for" : "You finished"} #${place}`
    this.finalScoreTarget.textContent = me?.pts ?? 0
    this.phaseGameOverTarget.classList.remove("hidden")
    if (place === 1) celebrateWin(this.gameOverIconTarget)
    else pop(this.gameOverIconTarget)
  }

  // ── Board ─────────────────────────────────────────────────────────────────

  tap(event) {
    const card = event.target.closest("[data-index]")
    if (!card || !this.active || this.pending || this.resolving) return
    if (card.dataset.state !== "down") return

    event.preventDefault()
    this.pending = true
    this.playSound(this.flipSound)
    this.channel.perform("flip", { index: Number(card.dataset.index) })
  }

  newBoard(cols, rows, force = false) {
    if (!cols || !rows) return
    this.pairs = cols * rows / 2
    this.items = {}
    this.openIndex = null
    this.setMatches(0)
    if (!force && cols === this.cols && rows === this.rows) return

    this.cols = cols
    this.rows = rows
    buildBoard(this.boardTarget, cols, rows, `calc(min(92vw, 68vh) / ${cols} * 0.45)`)
  }

  // Puts back what this player had found before the page reloaded.
  restoreBoard(board) {
    if (!board) return
    Object.entries(board.matched || {}).forEach(([i, item]) => {
      this.items[i] = item
      const card = cardAt(this.boardTarget, i)
      if (card) showFace(card, item, "matched")
    })
    if (board.open) {
      this.items[board.open.index] = board.open.item
      this.openIndex = board.open.index
      showFace(cardAt(this.boardTarget, board.open.index), board.open.item)
    }
    this.setMatches(board.matches || 0)
  }

  startPlaying(seconds, total = seconds) {
    this.hideCover()
    this.active = this.matches < this.pairs
    this.setStatus(this.active ? "Find the pairs!" : "All pairs found — wait for the others")
    this.setFeedback("")
    this.startCountdown(seconds, total)
  }

  // ── UI helpers ────────────────────────────────────────────────────────────

  showCover(title, hint) {
    this.coverTitleTarget.textContent = title
    this.coverHintTarget.textContent  = hint
    this.coverTarget.classList.remove("hidden")
    restartAnimation(this.coverTarget, "mp-slide")
  }

  hideCover() {
    this.coverTarget.classList.add("hidden")
  }

  setScore(score) {
    this.scoreTarget.textContent = score
  }

  setMatches(matches) {
    this.matches = matches
    this.pairsTarget.textContent = this.pairs ? `${matches}/${this.pairs} pairs` : ""
  }

  setStatus(text) {
    this.statusTarget.textContent = text
  }

  setFeedback(text, color = "#fff") {
    this.feedbackTarget.textContent = text
    this.feedbackTarget.style.color = color
    if (text) restartAnimation(this.feedbackTarget, "mp-pop")
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

  // ── Feedback ──────────────────────────────────────────────────────────────

  // Restarts the sound so quick taps each get their own play.
  playSound(audio) {
    audio.currentTime = 0
    audio.play().catch(() => {}) // ignore autoplay blocks
  }

  vibrate(pattern) {
    navigator.vibrate?.(pattern)
  }
}
