import { Controller } from "@hotwired/stimulus"
import consumer from "../channels/consumer"

export default class extends Controller {
  static values  = { roomCode: String }
  static targets = [
    "phaseWaiting", "phaseCategory", "phaseReveal", "phaseGameOver",
    "playerList", "roundLabel", "categoryText", "timerDisplay", "submissionsList",
    "revealCategory", "groupsList", "scoresList",
    "finalScores"
  ]

  connect() {
    this.channel = consumer.subscriptions.create(
      { channel: "Games::MindMatchChannel", room_code: this.roomCodeValue },
      {
        connected:    () => this.onConnected(),
        disconnected: () => {},
        received:     (data) => this.handleMessage(data)
      }
    )
    this.nicknames     = {}
    this.countdownTimer = null
  }

  disconnect() {
    this.channel?.unsubscribe()
    clearInterval(this.countdownTimer)
  }

  // ── ActionCable callbacks ────────────────────────────────────────────

  onConnected() {
    // Host triggers the game loop once the connection is up
    this.channel.perform("start_game_loop", {})
  }

  handleMessage(data) {
    switch (data.action) {
      case "state_snapshot":    return this.onStateSnapshot(data.state)
      case "player_presence":   return this.onPlayerPresence(data)
      case "show_category":     return this.onShowCategory(data)
      case "player_submitted":  return this.onPlayerSubmitted(data)
      case "reveal":            return this.onReveal(data)
      case "game_over":         return this.onGameOver(data)
      case "game_restarted":    return this.onGameRestarted(data)
    }
  }

  // ── Message handlers ─────────────────────────────────────────────────

  onStateSnapshot(state) {
    this.nicknames = state.nicknames || {}
    this.renderPlayerList()

    if (state.status === "game_over") {
      this.showPhase("phaseGameOver")
      this.renderFinalScores(state.scores || {})
    } else if (state.status === "revealing") {
      // mid-reveal on reconnect — wait for next round
    } else {
      this.showPhase("phaseWaiting")
    }
  }

  onPlayerPresence(data) {
    if (data.connected && data.nickname) {
      this.nicknames[data.player_id] = data.nickname
    }
    this.renderPlayerList()
  }

  onShowCategory(data) {
    this.nicknames = data.nicknames || this.nicknames
    this.showPhase("phaseCategory")

    if (this.roundLabelTarget)
      this.roundLabelTarget.textContent = `Round ${data.round} / ${data.total_rounds}`
    if (this.categoryTextTarget)
      this.categoryTextTarget.textContent = data.category
    if (this.submissionsListTarget)
      this.submissionsListTarget.innerHTML = ""

    this.startCountdown(data.duration)
  }

  onPlayerSubmitted(data) {
    if (!this.submissionsListTarget) return
    const badge = document.createElement("span")
    badge.className = "px-3 py-1 bg-violet-600/30 border border-violet-500/50 rounded-full text-violet-300 text-xs font-semibold"
    badge.textContent = data.nickname
    this.submissionsListTarget.appendChild(badge)
  }

  onReveal(data) {
    this.stopCountdown()
    this.showPhase("phaseReveal")
    this.nicknames = data.nicknames || this.nicknames

    if (this.revealCategoryTarget)
      this.revealCategoryTarget.textContent = data.category

    this.renderGroups(data.groups || [], data.round_scores || {})
    this.renderScores(data.scores || {})
  }

  onGameOver(data) {
    this.stopCountdown()
    this.nicknames = data.nicknames || this.nicknames
    this.showPhase("phaseGameOver")
    this.renderFinalScores(data.scores || {})
  }

  onGameRestarted(_data) {
    this.nicknames = {}
    this.showPhase("phaseWaiting")
    if (this.playerListTarget) this.playerListTarget.innerHTML = ""
    if (this.submissionsListTarget) this.submissionsListTarget.innerHTML = ""
  }

  // ── Host action ──────────────────────────────────────────────────────

  restartGame() {
    this.channel.perform("restart_game", {})
  }

  // ── Rendering ────────────────────────────────────────────────────────

  renderPlayerList() {
    if (!this.playerListTarget) return
    this.playerListTarget.innerHTML = Object.entries(this.nicknames)
      .map(([, nick]) =>
        `<span class="px-4 py-2 bg-slate-800 border border-violet-500/40 rounded-full
                      text-violet-300 text-sm font-semibold">${this.esc(nick)}</span>`
      ).join("")
  }

  renderGroups(groups, roundScores) {
    if (!this.groupsListTarget) return

    const colors = ["border-yellow-400 bg-yellow-400/10", "border-violet-400 bg-violet-400/10", "border-slate-600 bg-slate-800"]

    this.groupsListTarget.innerHTML = groups.map((g, i) => {
      const n = g.player_ids.length
      const pts = n > 1 ? `+${n} pts each` : "No match"
      const nicks = g.player_ids.map(id => this.esc(this.nicknames[id] || id)).join(", ")
      const color = n > 1 ? (i === 0 ? colors[0] : colors[1]) : colors[2]
      return `
        <div class="border-2 ${color} rounded-2xl px-5 py-4 flex items-center justify-between gap-4">
          <div>
            <p class="text-white font-black text-xl">${this.esc(g.word)}</p>
            <p class="text-slate-400 text-xs mt-1">${nicks}</p>
          </div>
          <p class="text-sm font-bold ${n > 1 ? "text-yellow-400" : "text-slate-600"} whitespace-nowrap">${pts}</p>
        </div>`
    }).join("")
  }

  renderScores(scores) {
    if (!this.scoresListTarget) return
    this.scoresListTarget.innerHTML = this._sortedScoreRows(scores, "text-sm")
  }

  renderFinalScores(scores) {
    if (!this.finalScoresTarget) return
    this.finalScoresTarget.innerHTML = this._sortedScoreRows(scores, "text-base")
  }

  _sortedScoreRows(scores, sizeClass) {
    return Object.entries(scores)
      .sort(([, a], [, b]) => b - a)
      .map(([id, pts], i) => {
        const nick = this.esc(this.nicknames[id] || id)
        const medal = i === 0 ? "🥇" : i === 1 ? "🥈" : i === 2 ? "🥉" : `${i + 1}.`
        return `
          <div class="flex items-center justify-between px-5 py-3 bg-slate-800 rounded-xl">
            <span class="${sizeClass} text-white font-semibold">${medal} ${nick}</span>
            <span class="${sizeClass} text-violet-300 font-black">${pts}</span>
          </div>`
      }).join("")
  }

  // ── Timer ────────────────────────────────────────────────────────────

  startCountdown(seconds) {
    this.stopCountdown()
    let remaining = seconds
    this._setTimer(remaining)

    this.countdownTimer = setInterval(() => {
      remaining -= 1
      this._setTimer(remaining)
      if (remaining <= 0) this.stopCountdown()
    }, 1000)
  }

  stopCountdown() {
    clearInterval(this.countdownTimer)
    this.countdownTimer = null
  }

  _setTimer(n) {
    if (!this.timerDisplayTarget) return
    this.timerDisplayTarget.textContent = Math.max(0, n)
    const urgent = n <= 5
    this.timerDisplayTarget.classList.toggle("border-red-500",    urgent)
    this.timerDisplayTarget.classList.toggle("text-red-400",      urgent)
    this.timerDisplayTarget.classList.toggle("border-violet-500", !urgent)
    this.timerDisplayTarget.classList.toggle("text-violet-400",   !urgent)
  }

  // ── Phase switch ─────────────────────────────────────────────────────

  showPhase(name) {
    const phases = ["phaseWaiting", "phaseCategory", "phaseReveal", "phaseGameOver"]
    phases.forEach(p => {
      const el = this[`${p}Target`]
      if (el) el.classList.toggle("hidden", p !== name)
    })
  }

  esc(str) {
    return String(str)
      .replace(/&/g, "&amp;")
      .replace(/</g, "&lt;")
      .replace(/>/g, "&gt;")
      .replace(/"/g, "&quot;")
  }
}
