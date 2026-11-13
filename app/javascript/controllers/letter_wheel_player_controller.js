import { Controller } from "@hotwired/stimulus"
import consumer from "channels/consumer"
import { t, num, placeTitle } from "controllers/shared/i18n"
import { celebrateWin } from "controllers/shared/celebration"
import { startCountdown, stopCountdown } from "controllers/haunted_house/common"
import { WheelSounds } from "controllers/letter_wheel/sounds"

const SEND_MARGIN = 300 // ms before the time runs out: what's typed is sent, so it still counts

// A phone. Shows the clue and a box to type the answer: one try per word, and the server says right
// or wrong at once ("answer_result"). Whatever is typed when the time runs out is sent too.
export default class extends Controller {
  static values  = { roomCode: String, playerId: String }
  static targets = [
    "phaseMessage", "messageTitle", "messageHint", "messageCountdown", "messagePoints",
    "phaseAnswer", "letter", "countdown", "hint", "clue", "input",
    "phaseGameOver", "gameOverTitle", "gameOverWords"
  ]

  connect() {
    this.state  = null
    this.round  = null
    this.sent   = false
    this.result = null
    this.sounds = new WheelSounds()
    this.keepAwake()

    this.channel = consumer.subscriptions.create(
      { channel: "Games::LetterWheelChannel", room_code: this.roomCodeValue, player_id: this.playerIdValue },
      {
        rejected: () => window.location.reload(),
        received: (data) => this.handleMessage(data)
      }
    )
  }

  disconnect() {
    document.removeEventListener("visibilitychange", this.onVisible)
    stopCountdown(this.countdownTarget)
    stopCountdown(this.messageCountdownTarget)
    clearTimeout(this.sendTimer)
    this.wakeLock?.release().catch(() => {})
    this.sounds.close()
    this.channel?.unsubscribe()
  }

  handleMessage(data) {
    switch (data.action) {
      case "state":          this.onState(data.state); break
      case "answer_result":  this.onResult(data); break
      case "player_left":    this.channel.perform("sync", {}); break
      case "game_restarted": window.location.reload(); break
      case "game_changed":   window.location.href = `/rooms/${this.roomCodeValue}`; break
    }
  }

  send(event) {
    event?.preventDefault()
    const text = this.inputTarget.value.trim()
    if (this.sent || this.state?.phase !== "clue" || !text) return

    this.sent = true
    this.sounds.unlock()
    clearTimeout(this.sendTimer)
    this.inputTarget.blur()
    this.channel.perform("answer", { text })
    this.render()
  }

  onResult({ right, points }) {
    this.result = { right, points }
    if (right) { this.sounds.right(); navigator.vibrate?.([ 40, 30, 80 ]) }
    else { this.sounds.wrong(); navigator.vibrate?.(200) }
    this.render()
  }

  onState(state) {
    const previous = this.state?.phase
    if (state.round !== this.round) {
      this.round  = state.round
      this.sent   = false
      this.result = null
      this.inputTarget.value = ""
    }
    this.state = state
    if ((state.answered || []).includes(this.playerIdValue)) this.sent = true
    const guess = state.guesses?.[this.playerIdValue]
    if (guess && !this.result) this.result = { right: guess.right, points: state.round_points?.[this.playerIdValue] || 0 }

    clearTimeout(this.sendTimer)
    if (state.phase === "intro") startCountdown(this.messageCountdownTarget, state.seconds_left)
    else stopCountdown(this.messageCountdownTarget)
    if (state.phase === "clue" && !this.sent) {
      startCountdown(this.countdownTarget, state.seconds_left)
      this.sendTimer = setTimeout(() => this.send(), state.seconds_left * 1000 - SEND_MARGIN)
    } else {
      stopCountdown(this.countdownTarget)
    }
    this.render()

    if (previous === state.phase || !previous) return
    if (state.phase === "clue" && !this.sent) this.inputTarget.focus()
    if (state.phase === "game_over" && this.place() === 1) celebrateWin(this.gameOverTitleTarget)
  }

  // ── Rendering ─────────────────────────────────────────────────────────────

  render() {
    const { phase } = this.state
    const answering = phase === "clue" && !this.sent
    this.phaseAnswerTarget.classList.toggle("hidden", !answering)
    this.phaseMessageTarget.classList.toggle("hidden", answering || phase === "game_over")
    this.phaseGameOverTarget.classList.toggle("hidden", phase !== "game_over")
    this.messagePointsTarget.textContent = this.summary()

    if (answering) this.showClue()
    else if (phase === "game_over") this.showGameOver()
    else this.showMessage()
  }

  showClue() {
    const { letter, contains, clue } = this.state
    this.letterTarget.textContent = letter.toUpperCase()
    this.hintTarget.textContent   = t(contains ? "letter_wheel.contains" : "letter_wheel.starts_with", { letter: letter.toUpperCase() })
    this.clueTarget.textContent   = clue
  }

  showMessage() {
    const { phase, answer } = this.state
    const verdict = this.result?.right ? `${t("letter_wheel.right")} +${num(this.result.points)}`
      : this.result ? t("letter_wheel.wrong") : null
    const messages = {
      intro:  [ t("letter_wheel.ready"), t("letter_wheel.starts_in") ],
      clue:   [ verdict ?? t("letter_wheel.sent"), t("letter_wheel.wait_others") ],
      reveal: [ verdict ?? t("letter_wheel.time_up"), this.revealHint(answer) ]
    }
    const [ title, hint ] = messages[phase] ?? [ t("letter_wheel.get_ready"), t("letter_wheel.look_tv") ]
    this.messageTitleTarget.textContent = title
    this.messageHintTarget.textContent  = hint
    this.messageTitleTarget.classList.toggle("text-green-400", !!this.result?.right)
    this.messageTitleTarget.classList.toggle("text-red-400", !!this.result && !this.result.right)
  }

  // The answer, and what this player wrote when it was wrong (so they can see how close they were).
  revealHint(answer) {
    const mine = this.state.guesses?.[this.playerIdValue]
    const hint = t("letter_wheel.answer_was", { answer })
    return mine && !mine.right ? `${hint} · ${t("letter_wheel.you_wrote", { text: mine.text })}` : hint
  }

  showGameOver() {
    this.gameOverTitleTarget.textContent = placeTitle(this.place())
    this.gameOverWordsTarget.textContent = this.summary()
  }

  summary() {
    const { correct = {}, scores = {} } = this.state
    const words = t("letter_wheel.words", { count: correct[this.playerIdValue] || 0 })
    return `${words} · ${t("shared.pts", { points: num(scores[this.playerIdValue]) })}`
  }

  // 1 + the players with more words, or as many words and more points. Tied players share a place.
  place() {
    const { correct = {}, scores = {} } = this.state
    const me = this.playerIdValue
    const better = (id) => (correct[id] || 0) > (correct[me] || 0) ||
      ((correct[id] || 0) === (correct[me] || 0) && (scores[id] || 0) > (scores[me] || 0))
    return 1 + Object.keys(scores).filter(better).length
  }

  // The phone stays awake while it waits for the TV.
  async keepAwake() {
    if (!("wakeLock" in navigator)) return
    const request = async () => { try { this.wakeLock = await navigator.wakeLock.request("screen") } catch {} }
    this.onVisible = () => { if (document.visibilityState === "visible") request() }
    document.addEventListener("visibilitychange", this.onVisible)
    request()
  }
}
