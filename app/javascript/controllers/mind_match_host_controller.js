import { Controller } from "@hotwired/stimulus"
import consumer from "channels/consumer"

export default class extends Controller {
  static values  = { roomCode: String }
  static targets = [
    "phaseWaiting", "phaseTransition", "phaseCategory", "phaseReveal", "phaseGameOver",
    "playerList",
    "transitionLabel", "transitionCountdown",
    "roundLabel", "categoryCard", "categoryText", "timerDisplay",
    "submissionsList", "submissionCount", "submissionBar",
    "revealCategory", "answersGrid", "scoresList",
    "finalScores",
    "toastContainer"
  ]

  connect() {
    this.injectStyles()
    this.channel = consumer.subscriptions.create(
      { channel: "Games::MindMatchChannel", room_code: this.roomCodeValue },
      {
        connected:    () => this.onConnected(),
        disconnected: () => {},
        received:     (data) => this.handleMessage(data)
      }
    )
    this.nicknames      = {}
    this.totalPlayers   = 0
    this.submittedCount = 0
    this.countdownTimer = null
  }

  disconnect() {
    this.channel?.unsubscribe()
    clearInterval(this.countdownTimer)
    clearInterval(this.transitionTimer)
  }

  // ── ActionCable ──────────────────────────────────────────────────────

  onConnected() {
    this.channel.perform("start_game_loop", {})
  }

  handleMessage(data) {
    switch (data.action) {
      case "state_snapshot":    return this.onStateSnapshot(data.state)
      case "player_presence":   return this.onPlayerPresence(data)
      case "next_round":        return this.onNextRound(data)
      case "show_category":     return this.onShowCategory(data)
      case "player_submitted":  return this.onPlayerSubmitted(data)
      case "reveal":            return this.onReveal(data)
      case "game_over":         return this.onGameOver(data)
      case "game_restarted":    return this.onGameRestarted(data)
      case "game_changed":      window.location.href = `/rooms/${this.roomCodeValue}`; break
    }
  }

  // ── Handlers ─────────────────────────────────────────────────────────

  onStateSnapshot(state) {
    this.nicknames    = state.nicknames     || {}
    this.totalPlayers = state.total_players || 0
    this.renderPlayerList()

    if (state.status === "game_over") {
      this.showPhase("phaseGameOver")
      this.renderFinalScores(state.scores || {})
    } else {
      this.showPhase("phaseWaiting")
    }
  }

  onPlayerPresence(data) {
    if (data.connected && data.nickname) {
      this.nicknames[data.player_id] = data.nickname
      this.totalPlayers = Object.keys(this.nicknames).length
    } else if (!data.connected) {
      // keep nickname for display but track count
      this.totalPlayers = Object.keys(this.nicknames).length
    }
    this.renderPlayerList()
  }

  onNextRound(data) {
    this.stopCountdown()
    this.showPhase("phaseTransition")

    if (this.transitionLabelTarget)
      this.transitionLabelTarget.textContent = `Round ${data.round} of ${data.total_rounds}`

    // Client-side 3 → 2 → 1 countdown matching TRANSITION_DURATION
    let n = 3
    if (this.transitionCountdownTarget) this.transitionCountdownTarget.textContent = n
    this.transitionTimer = setInterval(() => {
      n -= 1
      if (this.transitionCountdownTarget) this.transitionCountdownTarget.textContent = Math.max(0, n)
      if (n <= 0) { clearInterval(this.transitionTimer); this.transitionTimer = null }
    }, 1000)
  }

  onShowCategory(data) {
    this.nicknames      = data.nicknames     || this.nicknames
    this.totalPlayers   = data.total_players || this.totalPlayers
    this.submittedCount = 0
    this.showPhase("phaseCategory")

    if (this.roundLabelTarget)
      this.roundLabelTarget.textContent = `Round ${data.round} / ${data.total_rounds}`
    if (this.categoryTextTarget)
      this.categoryTextTarget.textContent = data.category
    if (this.submissionsListTarget)
      this.submissionsListTarget.innerHTML = ""

    this._updateSubmissionCount()
    this._animateCategoryCard()
    this.startCountdown(data.duration)
  }

  onPlayerSubmitted(data) {
    this.submittedCount += 1
    this._updateSubmissionCount()

    if (!this.submissionsListTarget) return
    const badge = document.createElement("span")
    badge.className = "mm-badge-in px-3 py-1 bg-violet-600/30 border border-violet-500/50 rounded-full text-violet-300 text-xs font-semibold"
    badge.textContent = data.nickname
    this.submissionsListTarget.appendChild(badge)
  }

  onReveal(data) {
    this.stopCountdown()
    this.showPhase("phaseReveal")
    this.nicknames = data.nicknames || this.nicknames

    if (this.revealCategoryTarget)
      this.revealCategoryTarget.textContent = data.category

    this.renderPlayerAnswers(data.groups || [], data.answers || {}, data.round_scores || {})
    this.renderScores(data.scores || {})

    // Toast: biggest match group
    const top = (data.groups || []).find(g => g.player_ids.length > 1)
    if (top) {
      const n     = top.player_ids.length
      const nicks = top.player_ids.map(id => this.nicknames[id] || id).join(" & ")
      this.showToast(`🔥 ${n}-way match: "${top.word}" — ${nicks}`, "match")
    } else {
      this.showToast("🤔 No matches this round!", "info")
    }
  }

  onGameOver(data) {
    this.stopCountdown()
    this.nicknames = data.nicknames || this.nicknames
    this.showPhase("phaseGameOver")
    this.renderFinalScores(data.scores || {})

    const winner = Object.entries(data.scores || {})
      .sort(([, a], [, b]) => b - a)[0]
    if (winner) {
      const nick = this.nicknames[winner[0]] || winner[0]
      this.showToast(`🏆 ${nick} wins with ${winner[1]} points!`, "win")
    }
  }

  onGameRestarted(_data) {
    this.nicknames      = {}
    this.totalPlayers   = 0
    this.submittedCount = 0
    this.showPhase("phaseWaiting")
    if (this.playerListTarget)    this.playerListTarget.innerHTML    = ""
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

  // One card per player with the word exactly as they typed it. Cards are ordered by group
  // (biggest match first); players in the same match share a color. Non-submitters go last.
  renderPlayerAnswers(groups, answers, roundScores) {
    if (!this.answersGridTarget) return
    this.answersGridTarget.innerHTML = ""

    const matchColors = [
      "border-yellow-400 bg-yellow-400/10",
      "border-violet-400 bg-violet-400/10",
      "border-cyan-400 bg-cyan-400/10",
      "border-pink-400 bg-pink-400/10",
      "border-emerald-400 bg-emerald-400/10"
    ]
    const cards = []
    let matchIndex = 0

    groups.forEach(g => {
      const n     = g.player_ids.length
      const color = n > 1 ? matchColors[matchIndex++ % matchColors.length] : "border-slate-600 bg-slate-800"
      g.player_ids.forEach(id => cards.push({ id, word: answers[id] || g.word, n, color }))
    })

    Object.keys(this.nicknames)
      .filter(id => !cards.some(c => c.id === id))
      .forEach(id => cards.push({ id, word: null, n: 0, color: "border-slate-700 bg-slate-900 opacity-60" }))

    cards.forEach((c, i) => {
      const pts   = roundScores[c.id] ?? c.n
      const label = c.n > 1 ? `${c.n}-way match · +${pts}` : c.n === 1 ? `Unique · +${pts}` : "0 pts"
      const word  = c.word === null
        ? `<p class="text-slate-500 italic text-xl">No answer</p>`
        : `<p class="text-white font-black text-2xl truncate">${this.esc(c.word)}</p>`

      const el = document.createElement("div")
      el.className = `mm-group-in border-2 ${c.color} rounded-2xl px-4 py-3 text-left min-w-0`
      el.style.animationDelay = `${i * 80}ms`
      el.innerHTML = `
        <p class="text-slate-300 text-sm font-semibold truncate">${this.esc(this.nicknames[c.id] || c.id)}</p>
        ${word}
        <p class="text-xs font-bold mt-1 ${c.n > 1 ? "text-yellow-400" : "text-slate-500"}">${label}</p>`
      this.answersGridTarget.appendChild(el)
    })
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
        const nick  = this.esc(this.nicknames[id] || id)
        const medal = i === 0 ? "🥇" : i === 1 ? "🥈" : i === 2 ? "🥉" : `${i + 1}.`
        return `
          <div class="flex items-center justify-between px-5 py-3 bg-slate-800 rounded-xl">
            <span class="${sizeClass} text-white font-semibold">${medal} ${nick}</span>
            <span class="${sizeClass} text-violet-300 font-black">${pts}</span>
          </div>`
      }).join("")
  }

  _updateSubmissionCount() {
    if (this.submissionCountTarget)
      this.submissionCountTarget.textContent =
        `${this.submittedCount} / ${this.totalPlayers} submitted`

    if (this.submissionBarTarget) {
      const pct = this.totalPlayers > 0
        ? Math.round((this.submittedCount / this.totalPlayers) * 100)
        : 0
      this.submissionBarTarget.style.width = `${pct}%`
    }
  }

  _animateCategoryCard() {
    const card = this.categoryCardTarget
    if (!card) return
    card.classList.remove("mm-category-in")
    // Force reflow so the animation restarts
    void card.offsetWidth
    card.classList.add("mm-category-in")
  }

  // ── Toast ─────────────────────────────────────────────────────────────

  showToast(msg, type = "info") {
    if (!this.toastContainerTarget) return
    const colors = {
      match: "bg-violet-700 border-violet-400",
      win:   "bg-yellow-700 border-yellow-400",
      info:  "bg-slate-700  border-slate-500"
    }
    const el = document.createElement("div")
    el.className = `mm-toast-in pointer-events-none px-5 py-3 rounded-2xl border shadow-xl
                    text-white text-sm font-semibold max-w-xs text-center ${colors[type] || colors.info}`
    el.textContent = msg
    this.toastContainerTarget.appendChild(el)

    setTimeout(() => {
      el.classList.remove("mm-toast-in")
      el.classList.add("mm-toast-out")
      el.addEventListener("animationend", () => el.remove(), { once: true })
    }, 3000)
  }

  // ── Timer ─────────────────────────────────────────────────────────────

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
    this.timerDisplayTarget.classList.toggle("mm-timer-pulse",    urgent)
  }

  // ── Phase switch ──────────────────────────────────────────────────────

  showPhase(name) {
    ["phaseWaiting", "phaseTransition", "phaseCategory", "phaseReveal", "phaseGameOver"].forEach(p => {
      const el = this[`${p}Target`]
      if (el) el.classList.toggle("hidden", p !== name)
    })
  }

  // ── CSS injection ─────────────────────────────────────────────────────

  injectStyles() {
    if (document.getElementById("mind-match-styles")) return
    const style = document.createElement("style")
    style.id = "mind-match-styles"
    style.textContent = `
      @keyframes mm-category-enter {
        from { opacity: 0; transform: scale(0.85) translateY(12px); }
        to   { opacity: 1; transform: scale(1)    translateY(0); }
      }
      @keyframes mm-group-enter {
        from { opacity: 0; transform: translateX(-16px); }
        to   { opacity: 1; transform: translateX(0); }
      }
      @keyframes mm-badge-enter {
        from { opacity: 0; transform: scale(0.7); }
        to   { opacity: 1; transform: scale(1); }
      }
      @keyframes mm-toast-slide-in {
        from { opacity: 0; transform: translateY(20px) scale(0.95); }
        to   { opacity: 1; transform: translateY(0)    scale(1); }
      }
      @keyframes mm-toast-slide-out {
        from { opacity: 1; transform: translateY(0)    scale(1); }
        to   { opacity: 0; transform: translateY(-10px) scale(0.95); }
      }
      @keyframes mm-timer-pulse-ring {
        0%, 100% { transform: scale(1); }
        50%      { transform: scale(1.12); }
      }

      .mm-category-in  { animation: mm-category-enter 0.4s cubic-bezier(0.34, 1.56, 0.64, 1) both; }
      .mm-group-in     { animation: mm-group-enter   0.35s ease both; }
      .mm-badge-in     { animation: mm-badge-enter   0.2s  ease both; }
      .mm-toast-in     { animation: mm-toast-slide-in  0.3s ease both; }
      .mm-toast-out    { animation: mm-toast-slide-out 0.3s ease both; }
      .mm-timer-pulse  { animation: mm-timer-pulse-ring 0.6s ease infinite; }
    `
    document.head.appendChild(style)
  }

  esc(str) {
    return String(str)
      .replace(/&/g, "&amp;")
      .replace(/</g, "&lt;")
      .replace(/>/g, "&gt;")
      .replace(/"/g, "&quot;")
  }
}
