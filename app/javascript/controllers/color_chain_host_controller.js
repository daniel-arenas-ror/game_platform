import { Controller } from "@hotwired/stimulus"
import consumer from "channels/consumer"
import { t, num } from "controllers/shared/i18n"
import { avatarHtml } from "controllers/shared/avatar"
import { escapeHtml } from "controllers/shared/html"
import { confetti } from "controllers/shared/celebration"
import { startCountdown, stopCountdown } from "controllers/haunted_house/common"
import { ChainSounds } from "controllers/color_chain/sounds"

const BOARD_SIZE = 8 // players listed beside the blocks

// The TV. Lights up the sequence on the four blocks, then waits for the phones and shows the
// sequence and the points. The server sends the state on every phase change ("state"), and the
// colours to this screen alone ("sequence").
export default class extends Controller {
  static values  = { roomCode: String }
  static targets = [
    "soundButton", "roundLabel", "status", "countdown", "block", "reveal", "revealSequence", "chip", "board",
    "phaseGameOver", "finalBoard"
  ]

  connect() {
    this.state     = null
    this.nicknames = {}
    this.timers    = []
    this.sounds    = new ChainSounds()
    this.soundLabel  = this.soundButtonTarget.textContent.trim().replace(/^\S+\s*/, "")
    this.unlockSound = () => this.sounds.unlock()
    document.addEventListener("pointerdown", this.unlockSound)

    this.channel = consumer.subscriptions.create(
      { channel: "Games::ColorChainChannel", room_code: this.roomCodeValue, player_id: "" },
      {
        connected: () => this.channel.perform("start_game_loop", {}),
        received:  (data) => this.handleMessage(data)
      }
    )
  }

  disconnect() {
    document.removeEventListener("pointerdown", this.unlockSound)
    this.stopPlayback()
    stopCountdown(this.countdownTarget)
    this.sounds.close()
    this.channel?.unsubscribe()
  }

  handleMessage(data) {
    switch (data.action) {
      case "state":          this.onState(data); break
      case "sequence":       this.play(data); break
      case "answered":       this.onAnswered(data); break
      case "player_left":    this.channel.perform("sync", {}); break
      case "game_restarted": window.location.reload(); break
      case "game_changed":   window.location.href = `/rooms/${this.roomCodeValue}`; break
      case "game_error":     this.statusTarget.textContent = t("color_chain.error"); break
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

    this.roundLabelTarget.textContent = state.round ? t("shared.round_of", { round: state.round, total: state.total_rounds }) : ""
    if (state.phase !== "watching") this.stopPlayback()
    else if (state.sequence && !this.playing) this.play(state) // this screen reloaded during playback

    if (state.phase === "input") startCountdown(this.countdownTarget, state.seconds_left)
    else stopCountdown(this.countdownTarget)

    this.renderStatus()
    this.renderBoard()
    this.renderReveal()
    this.phaseGameOverTarget.classList.toggle("hidden", state.phase !== "game_over")
    if (state.phase === "game_over") this.finalBoardTarget.innerHTML = this.boardHtml(this.ranking())

    if (previous === state.phase || !previous) return
    if (state.phase === "input") this.sounds.yourTurn()
    if (state.phase === "game_over") { this.sounds.win(); confetti(80) }
  }

  onAnswered({ player_id }) {
    if (!this.state) return
    this.state.answered = [ ...new Set([ ...(this.state.answered || []), player_id ]) ]
    this.renderStatus()
    this.renderBoard()
  }

  // ── Playback ──────────────────────────────────────────────────────────────

  play({ sequence, lead_in, flash_duration, flash_gap }) {
    this.stopPlayback()
    this.playing = true
    const flash = flash_duration * 1000
    const step  = flash + flash_gap * 1000

    sequence.forEach((color, i) => {
      const start = lead_in * 1000 + i * step
      this.timers.push(setTimeout(() => { this.light(color); this.sounds.color(color, flash_duration) }, start))
      this.timers.push(setTimeout(() => this.light(null), start + flash))
    })
    this.timers.push(setTimeout(() => { this.playing = false }, lead_in * 1000 + sequence.length * step))
  }

  stopPlayback() {
    this.timers.forEach(clearTimeout)
    this.timers  = []
    this.playing = false
    this.light(null)
  }

  light(color) {
    this.blockTargets.forEach((block) => {
      const on = block.dataset.color === color
      block.classList.toggle("opacity-25", !on)
      block.classList.toggle("scale-105", on)
    })
  }

  // ── Rendering ─────────────────────────────────────────────────────────────

  renderStatus() {
    const { phase, answered = [], scores = {} } = this.state
    const messages = {
      watching: t("color_chain.watch"),
      input:    t("color_chain.answered", { done: answered.length, total: Object.keys(scores).length }),
      reveal:   t("color_chain.results")
    }
    this.statusTarget.textContent = messages[phase] ?? t("color_chain.get_ready")
  }

  renderReveal() {
    const { phase, sequence = [] } = this.state
    this.revealTarget.classList.toggle("hidden", phase !== "reveal")
    if (phase !== "reveal") return

    this.revealSequenceTarget.querySelectorAll("span").forEach((chip) => chip.remove())
    sequence.forEach((color) => {
      const chip = this.chipTargets.find((template) => template.dataset.color === color)
      this.revealSequenceTarget.append(chip.content.cloneNode(true))
    })
  }

  renderBoard() {
    this.boardTarget.innerHTML = this.boardHtml(this.ranking().slice(0, BOARD_SIZE))
  }

  // Highest first. Players the TV has no name for yet (just joined) wait for the next state.
  ranking() {
    return Object.entries(this.state.scores || {})
      .filter(([ id ]) => this.nicknames[id])
      .map(([ id, points ]) => ({ id, points, name: this.nicknames[id] }))
      .sort((a, b) => b.points - a.points)
  }

  boardHtml(rows) {
    const { phase, answered = [], round_scores: won = {} } = this.state
    return rows.map(({ id, points, name }) => {
      const note = phase === "input" && answered.includes(id) ? "✓" : phase === "reveal" ? `+${num(won[id])}` : ""
      return `<div class="flex items-center gap-3 rounded-xl border border-slate-700 bg-slate-800 px-3 py-2">
        ${avatarHtml(name, "size-8")}
        <span class="flex-1 min-w-0 truncate font-bold">${escapeHtml(name)}</span>
        <span class="text-green-400 font-bold tabular-nums">${note}</span>
        <span class="font-black tabular-nums">${num(points)}</span>
      </div>`
    }).join("")
  }
}
