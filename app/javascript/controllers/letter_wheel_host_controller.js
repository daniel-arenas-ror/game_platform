import { Controller } from "@hotwired/stimulus"
import consumer from "channels/consumer"
import { t, num } from "controllers/shared/i18n"
import { avatarHtml } from "controllers/shared/avatar"
import { escapeHtml } from "controllers/shared/html"
import { confetti } from "controllers/shared/celebration"
import { startCountdown, stopCountdown } from "controllers/haunted_house/common"
import { WheelSounds } from "controllers/letter_wheel/sounds"

const BOARD_SIZE = 8  // players listed beside the ring
const TICK_FROM  = 5  // seconds left when the countdown starts ticking
const RING_SIZE  = 9  // each letter's bubble, in % of the ring
const BUBBLE     = "absolute flex items-center justify-center rounded-full border-2 font-black transition-[background-color,scale] duration-300"

// The TV. The letters sit around a ring with the current clue in the middle; each letter turns green
// (most players got it), orange (some did) or red (nobody) once it's over. The server sends the state
// on every phase change ("state") and each answer as it comes in ("answered").
export default class extends Controller {
  static values  = { roomCode: String }
  static targets = [
    "soundButton", "roundLabel", "ring", "hint", "clue", "answer", "countdown", "status", "board",
    "phaseGameOver", "finalBoard", "solutions"
  ]

  connect() {
    this.state      = null
    this.nicknames  = {}
    this.sounds     = new WheelSounds()
    this.soundLabel = this.soundButtonTarget.textContent.trim().replace(/^\S+\s*/, "")

    this.channel = consumer.subscriptions.create(
      { channel: "Games::LetterWheelChannel", room_code: this.roomCodeValue, player_id: "" },
      {
        connected: () => this.channel.perform("start_game_loop", {}),
        received:  (data) => this.handleMessage(data)
      }
    )
  }

  disconnect() {
    stopCountdown(this.countdownTarget)
    this.sounds.close()
    this.channel?.unsubscribe()
  }

  handleMessage(data) {
    switch (data.action) {
      case "state":          this.onState(data); break
      case "answered":       this.onAnswered(data); break
      case "player_left":    this.channel.perform("sync", {}); break
      case "game_restarted": window.location.reload(); break
      case "game_changed":   window.location.href = `/rooms/${this.roomCodeValue}`; break
      case "game_error":     this.clueTarget.textContent = t("letter_wheel.error"); break
    }
  }

  restart(event) {
    event.currentTarget.disabled = true
    this.channel.perform("restart_game", {})
  }

  toggleSound() {
    const on = this.sounds.toggle()
    this.soundButtonTarget.textContent = `${on ? "🔊" : "🔇"} ${this.soundLabel}`
    this.soundButtonTarget.classList.toggle("opacity-50", !on)
  }

  onState({ state, nicknames }) {
    const previous = this.state?.phase
    this.state     = state
    this.nicknames = nicknames || {}

    this.roundLabelTarget.textContent = state.round ? t("letter_wheel.letter_of", { round: state.round, total: state.total_rounds }) : ""
    if (state.phase === "clue") startCountdown(this.countdownTarget, state.seconds_left, (left) => this.onTick(left))
    else stopCountdown(this.countdownTarget)

    this.renderRing()
    this.renderCenter()
    this.renderBoard()
    this.phaseGameOverTarget.classList.toggle("hidden", state.phase !== "game_over")
    if (state.phase === "game_over") this.renderGameOver()

    if (previous === state.phase || !previous) return
    if (state.phase === "clue") this.sounds.clue()
    if (state.phase === "reveal") this.sounds.reveal()
    if (state.phase === "game_over") { this.sounds.win(); confetti(80) }
  }

  onAnswered({ player_id }) {
    if (!this.state) return
    this.state.answered = [ ...new Set([ ...(this.state.answered || []), player_id ]) ]
    this.renderCenter()
    this.renderBoard()
  }

  onTick(left) {
    if (left === this.lastTick) return
    this.lastTick = left
    if (left > 0 && left <= TICK_FROM) this.sounds.tick()
  }

  // ── Rendering ─────────────────────────────────────────────────────────────

  // One bubble per letter, clockwise from the top. Rebuilt when the letters change (a new game).
  renderRing() {
    const { letters = [], results = {}, round = 0, phase } = this.state
    if (this.ringLetters !== letters.join()) {
      this.ringLetters = letters.join()
      this.ringTarget.querySelectorAll("[data-letter]").forEach((bubble) => bubble.remove())
      letters.forEach((letter, i) => {
        const angle  = (i / letters.length) * 2 * Math.PI
        const bubble = document.createElement("span")
        bubble.dataset.letter = letter
        bubble.textContent    = letter.toUpperCase()
        Object.assign(bubble.style, {
          width: `${RING_SIZE}%`, height: `${RING_SIZE}%`, fontSize: "4.4cqmin",
          left: `${50 + 45 * Math.sin(angle) - RING_SIZE / 2}%`, top: `${50 - 45 * Math.cos(angle) - RING_SIZE / 2}%`
        })
        this.ringTarget.append(bubble)
      })
    }

    const current = phase === "clue" ? letters[round - 1] : null
    this.ringTarget.querySelectorAll("[data-letter]").forEach((bubble) => {
      const letter = bubble.dataset.letter
      const share  = results[letter]
      const look   = letter === current ? "bg-white text-slate-950 border-white scale-125"
        : share == null ? "bg-slate-800 text-slate-300 border-slate-700"
        : share >= 0.5  ? "bg-green-500 text-white border-green-400"
        : share > 0     ? "bg-orange-500 text-white border-orange-400"
        :                 "bg-red-500 text-white border-red-400"
      bubble.className = `${BUBBLE} ${look}`
    })
  }

  renderCenter() {
    const { phase, letter, contains, clue, answer, answered = [], scores = {}, guesses = {} } = this.state
    const showing = phase === "clue" || phase === "reveal"
    const total   = Object.keys(scores).length

    this.hintTarget.textContent = showing ? t(contains ? "letter_wheel.contains" : "letter_wheel.starts_with", { letter: letter.toUpperCase() }) : ""
    this.clueTarget.textContent = showing ? clue : phase === "game_over" ? "" : t("letter_wheel.get_ready")
    this.answerTarget.classList.toggle("hidden", phase !== "reveal")
    this.answerTarget.textContent = answer || ""

    const right = Object.values(guesses).filter((guess) => guess.right).length
    this.statusTarget.textContent =
      phase === "clue"   ? t("letter_wheel.answered", { done: answered.length, total }) :
      phase === "reveal" ? t("letter_wheel.got_it", { count: right, total }) : ""
  }

  renderBoard() {
    this.boardTarget.innerHTML = this.boardHtml(this.ranking().slice(0, BOARD_SIZE))
  }

  renderGameOver() {
    this.finalBoardTarget.innerHTML = this.boardHtml(this.ranking())
    this.solutionsTarget.innerHTML = (this.state.solutions || []).map(({ letter, answer }) => {
      const share = this.state.results?.[letter]
      const color = share >= 0.5 ? "border-green-500" : share > 0 ? "border-orange-500" : "border-red-500"
      return `<span class="rounded-lg border-2 ${color} bg-slate-900 px-2 py-1 text-sm font-bold">
        <span class="text-amber-400">${escapeHtml(letter.toUpperCase())}</span> ${escapeHtml(answer)}</span>`
    }).join("")
  }

  // Most words first, then points (the server's order at game over). Players the TV has no name
  // for yet (just joined) wait for the next state.
  ranking() {
    const { scores = {}, correct = {}, ranking } = this.state
    const ids = ranking || Object.keys(scores).sort((a, b) => (correct[b] || 0) - (correct[a] || 0) || scores[b] - scores[a])
    return ids.filter((id) => this.nicknames[id])
      .map((id) => ({ id, name: this.nicknames[id], words: correct[id] || 0, points: scores[id] || 0 }))
  }

  boardHtml(rows) {
    const { phase, answered = [], guesses = {}, round_points: won = {} } = this.state
    return rows.map(({ id, name, words, points }) => {
      const note = phase === "clue" && answered.includes(id) ? `<span class="text-slate-300">✓</span>`
        : phase === "reveal" && guesses[id]?.right ? `<span class="text-green-400">+${num(won[id])}</span>`
        : phase === "reveal" && guesses[id] ? `<span class="text-red-400">✗</span>` : ""
      return `<div class="flex items-center gap-3 rounded-xl border border-slate-700 bg-slate-800 px-3 py-2">
        ${avatarHtml(name, "size-8")}
        <span class="flex-1 min-w-0 truncate font-bold">${escapeHtml(name)}</span>
        <span class="font-bold tabular-nums">${note}</span>
        <span class="text-right leading-tight">
          <span class="block font-black tabular-nums text-amber-400">${t("letter_wheel.words", { count: words })}</span>
          <span class="block text-xs text-slate-400 tabular-nums">${t("shared.pts", { points: num(points) })}</span>
        </span>
      </div>`
    }).join("")
  }
}
