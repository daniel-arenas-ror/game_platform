import { Controller } from "@hotwired/stimulus"
import consumer from "channels/consumer"
import { t, num, placeTitle } from "controllers/shared/i18n"
import { startCountdown, stopCountdown } from "controllers/haunted_house/common"

const SEND_MARGIN = 300 // ms before the time runs out, so a phone's last taps reach the server

// A phone. Four blocks fill the screen while the player repeats the sequence, and the answer goes
// to the server after the last tap or when the time runs out. A phone never gets the colours
// before the reveal, so it can't tell a wrong tap.
export default class extends Controller {
  static values  = { roomCode: String, playerId: String }
  static targets = [
    "phaseMessage", "messageTitle", "messageHint", "messagePoints",
    "phaseBlocks", "blocksPoints", "taps", "countdown",
    "phaseGameOver", "gameOverTitle", "gameOverPoints"
  ]

  connect() {
    this.state = null
    this.round = null
    this.tapped = []
    this.sent  = false
    this.keepAwake()

    this.channel = consumer.subscriptions.create(
      { channel: "Games::ColorChainChannel", room_code: this.roomCodeValue, player_id: this.playerIdValue },
      {
        rejected: () => window.location.reload(),
        received: (data) => this.handleMessage(data)
      }
    )
  }

  disconnect() {
    document.removeEventListener("visibilitychange", this.onVisible)
    stopCountdown(this.countdownTarget)
    clearTimeout(this.sendTimer)
    this.wakeLock?.release().catch(() => {})
    this.channel?.unsubscribe()
  }

  handleMessage(data) {
    switch (data.action) {
      case "state":          this.onState(data.state); break
      case "player_left":    this.channel.perform("sync", {}); break
      case "game_restarted": window.location.reload(); break
      case "game_changed":   window.location.href = `/rooms/${this.roomCodeValue}`; break
    }
  }

  tap(event) {
    if (this.state?.phase !== "input" || this.sent) return

    this.tapped.push(event.currentTarget.dataset.color)
    this.renderTaps()
    if (this.tapped.length >= this.state.sequence_length) this.send()
  }

  send() {
    if (this.sent) return
    this.sent = true
    clearTimeout(this.sendTimer)
    this.channel.perform("answer", { colors: this.tapped })
    this.render()
  }

  onState(state) {
    if (state.round !== this.round) {
      this.round  = state.round
      this.tapped = []
      this.sent   = false
    }
    this.state = state
    if ((state.answered || []).includes(this.playerIdValue)) this.sent = true

    clearTimeout(this.sendTimer)
    if (state.phase === "input" && !this.sent) {
      startCountdown(this.countdownTarget, state.seconds_left)
      this.sendTimer = setTimeout(() => this.send(), state.seconds_left * 1000 - SEND_MARGIN)
    } else {
      stopCountdown(this.countdownTarget)
    }
    this.render()
  }

  // ── Rendering ─────────────────────────────────────────────────────────────

  render() {
    const { phase } = this.state
    const blocks = phase === "input" && !this.sent
    this.phaseBlocksTarget.classList.toggle("hidden", !blocks)
    this.phaseMessageTarget.classList.toggle("hidden", blocks || phase === "game_over")
    this.phaseGameOverTarget.classList.toggle("hidden", phase !== "game_over")

    const points = t("shared.pts", { points: num(this.myPoints()) })
    this.blocksPointsTarget.textContent   = points
    this.messagePointsTarget.textContent  = points
    this.gameOverPointsTarget.textContent = points
    this.renderTaps()

    if (phase === "game_over") this.showGameOver()
    else this.showMessage()
  }

  renderTaps() {
    this.tapsTarget.textContent = `${this.tapped.length} / ${this.state.sequence_length}`
  }

  showMessage() {
    const { phase, round_scores: won = {} } = this.state
    const messages = {
      watching: [ t("color_chain.watch"), t("color_chain.look_tv") ],
      input:    [ t("color_chain.sent"), t("color_chain.wait_others") ],
      reveal:   [ `+${num(won[this.playerIdValue])}`, t("color_chain.look_tv") ]
    }
    const [ title, hint ] = messages[phase] ?? [ t("color_chain.get_ready"), t("color_chain.look_tv") ]
    this.messageTitleTarget.textContent = title
    this.messageHintTarget.textContent  = hint
  }

  showGameOver() {
    const scores = Object.values(this.state.scores || {})
    this.gameOverTitleTarget.textContent = placeTitle(1 + scores.filter((points) => points > this.myPoints()).length)
  }

  myPoints() {
    return this.state.scores?.[this.playerIdValue] ?? 0
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
