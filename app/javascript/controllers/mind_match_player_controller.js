import { Controller } from "@hotwired/stimulus"
import consumer from "channels/consumer"

export default class extends Controller {
  static values  = { roomCode: String, playerId: String }
  static targets = [
    "phaseWaiting", "phaseTransition", "phaseTyping", "phaseReveal", "phaseGameOver",
    "transitionLabel", "transitionCountdown",
    "timerDisplay", "categoryCard", "categoryText",
    "wordInput", "submitBtn", "inputArea", "submittedMsg",
    "revealCategory", "groupsList", "myScore", "roundPointsFlash",
    "finalScores",
    "toastContainer"
  ]

  connect() {
    this.injectStyles()
    this.channel = consumer.subscriptions.create(
      {
        channel:   "Games::MindMatchChannel",
        room_code: this.roomCodeValue,
        player_id: this.playerIdValue
      },
      {
        connected:    () => {},
        disconnected: () => {},
        received:     (data) => this.handleMessage(data)
      }
    )
    this.nicknames      = {}
    this.countdownTimer = null
    this.submitted      = false

    this.boundKeydown = (e) => { if (e.key === "Enter") this.submitWord() }
    document.addEventListener("keydown", this.boundKeydown)
  }

  disconnect() {
    this.channel?.unsubscribe()
    clearInterval(this.countdownTimer)
    clearInterval(this.transitionTimer)
    document.removeEventListener("keydown", this.boundKeydown)
  }

  // ── ActionCable ──────────────────────────────────────────────────────

  handleMessage(data) {
    switch (data.action) {
      case "state_snapshot":   return this.onStateSnapshot(data.state)
      case "next_round":       return this.onNextRound(data)
      case "show_category":    return this.onShowCategory(data)
      case "player_submitted": return this.onPlayerSubmitted(data)
      case "reveal":           return this.onReveal(data)
      case "game_over":        return this.onGameOver(data)
      case "game_restarted":   return this.onGameRestarted(data)
      case "game_changed":      window.location.href = `/rooms/${this.roomCodeValue}`; break
    }
  }

  // ── Handlers ─────────────────────────────────────────────────────────

  onStateSnapshot(state) {
    this.nicknames = state.nicknames || {}

    if (state.status === "game_over") {
      this.showPhase("phaseGameOver")
      this.renderFinalScores(state.scores || {})
    } else if (state.status === "collecting") {
      const alreadySubmitted = !!(state.answers || {})[this.playerIdValue]
      this.showPhase("phaseTyping")
      if (this.categoryTextTarget)
        this.categoryTextTarget.textContent = state.current_category || ""
      if (alreadySubmitted) this._markSubmitted()
    } else {
      this.showPhase("phaseWaiting")
    }
  }

  onNextRound(data) {
    this.stopCountdown()
    this.showPhase("phaseTransition")

    if (this.transitionLabelTarget)
      this.transitionLabelTarget.textContent = `Round ${data.round} of ${data.total_rounds}`

    let n = 3
    if (this.transitionCountdownTarget) this.transitionCountdownTarget.textContent = n
    this.transitionTimer = setInterval(() => {
      n -= 1
      if (this.transitionCountdownTarget) this.transitionCountdownTarget.textContent = Math.max(0, n)
      if (n <= 0) { clearInterval(this.transitionTimer); this.transitionTimer = null }
    }, 1000)
  }

  onShowCategory(data) {
    this.nicknames = data.nicknames || this.nicknames
    this.submitted = false
    this.showPhase("phaseTyping")

    if (this.categoryTextTarget)
      this.categoryTextTarget.textContent = data.category
    if (this.wordInputTarget)
      this.wordInputTarget.value = ""

    this._resetInput()
    this._animateCategoryCard()
    this.startCountdown(data.duration)
  }

  onPlayerSubmitted(data) {
    if (data.player_id === this.playerIdValue) {
      this._markSubmitted()
    }
  }

  onReveal(data) {
    this.stopCountdown()
    this.nicknames = data.nicknames || this.nicknames
    this.showPhase("phaseReveal")

    if (this.revealCategoryTarget)
      this.revealCategoryTarget.textContent = data.category

    const myPts = (data.round_scores || {})[this.playerIdValue] || 0
    const total  = (data.scores     || {})[this.playerIdValue] || 0

    this.renderGroupsStaggered(data.groups || [], data.round_scores || {})

    if (this.myScoreTarget) this.myScoreTarget.textContent = total

    // Toast feedback
    if (myPts > 1) {
      this.showToast(`✨ You matched! +${myPts} pts`, "match")
      this._flashPoints(myPts)
    } else if (myPts === 1) {
      // Solo answer still scores 1 (matched with self — shouldn't happen but just in case)
      this.showToast(`+1 pt`, "info")
    } else {
      this.showToast("😬 No match this round", "miss")
    }
  }

  onGameOver(data) {
    this.stopCountdown()
    this.nicknames = data.nicknames || this.nicknames
    this.showPhase("phaseGameOver")
    this.renderFinalScores(data.scores || {})

    const sorted = Object.entries(data.scores || {}).sort(([, a], [, b]) => b - a)
    const myRank = sorted.findIndex(([id]) => id === this.playerIdValue)
    if (myRank === 0) {
      this.showToast("🏆 You won! Congratulations!", "win")
    } else if (myRank >= 0) {
      this.showToast(`You finished #${myRank + 1}`, "info")
    }
  }

  onGameRestarted(_data) {
    this.stopCountdown()
    this.nicknames = {}
    this.submitted = false
    this.showPhase("phaseWaiting")
  }

  // ── Player action ────────────────────────────────────────────────────

  submitWord() {
    if (this.submitted) return
    const word = this.wordInputTarget?.value?.trim() || ""
    if (!word) {
      this._shakeInput()
      return
    }
    this.channel.perform("submit_word", { word })
    this.submitted = true
    this._markSubmitted()
  }

  // ── Rendering ────────────────────────────────────────────────────────

  renderGroupsStaggered(groups, roundScores) {
    if (!this.groupsListTarget) return
    this.groupsListTarget.innerHTML = ""
    const myId = this.playerIdValue

    groups.forEach((g, i) => {
      const n     = g.player_ids.length
      const isMe  = g.player_ids.includes(myId)
      const pts   = n > 1 ? `+${n} pts` : "No match"
      const nicks = g.player_ids.map(id => this.esc(this.nicknames[id] || id)).join(", ")

      let color = "border-slate-600 bg-slate-800"
      if (n > 1 && isMe)  color = "border-yellow-400 bg-yellow-400/10"
      else if (n > 1)     color = "border-violet-400 bg-violet-400/10"

      const el = document.createElement("div")
      el.className = `mm-group-in border-2 ${color} rounded-2xl px-5 py-4 flex items-center justify-between gap-4`
      el.style.animationDelay = `${i * 120}ms`
      el.innerHTML = `
        <div>
          <p class="text-white font-black text-lg">${this.esc(g.word)}</p>
          <p class="text-slate-400 text-xs mt-1">${nicks}</p>
        </div>
        <p class="text-sm font-bold ${n > 1 ? "text-yellow-400" : "text-slate-600"} whitespace-nowrap">${pts}</p>`
      this.groupsListTarget.appendChild(el)
    })
  }

  renderFinalScores(scores) {
    if (!this.finalScoresTarget) return
    const myId = this.playerIdValue

    this.finalScoresTarget.innerHTML = Object.entries(scores)
      .sort(([, a], [, b]) => b - a)
      .map(([id, pts], i) => {
        const nick      = this.esc(this.nicknames[id] || id)
        const isMe      = id === myId
        const medal     = i === 0 ? "🥇" : i === 1 ? "🥈" : i === 2 ? "🥉" : `${i + 1}.`
        const highlight = isMe ? "border border-violet-500/60 bg-violet-500/10" : "bg-slate-800"
        const youTag    = isMe ? ` <span class='text-violet-400 text-xs'>(you)</span>` : ""
        return `
          <div class="flex items-center justify-between px-5 py-3 ${highlight} rounded-xl">
            <span class="text-base text-white font-semibold">${medal} ${nick}${youTag}</span>
            <span class="text-base text-violet-300 font-black">${pts}</span>
          </div>`
      }).join("")
  }

  // ── Helpers ──────────────────────────────────────────────────────────

  _markSubmitted() {
    this.submitted = true
    this.stopCountdown()
    if (this.inputAreaTarget)    this.inputAreaTarget.classList.add("hidden")
    if (this.submittedMsgTarget) this.submittedMsgTarget.classList.remove("hidden")
  }

  _resetInput() {
    if (this.inputAreaTarget)    this.inputAreaTarget.classList.remove("hidden")
    if (this.submittedMsgTarget) this.submittedMsgTarget.classList.add("hidden")
    if (this.submitBtnTarget)    this.submitBtnTarget.disabled = false
  }

  _animateCategoryCard() {
    const card = this.categoryCardTarget
    if (!card) return
    card.classList.remove("mm-category-in")
    void card.offsetWidth
    card.classList.add("mm-category-in")
  }

  _flashPoints(pts) {
    if (!this.roundPointsFlashTarget) return
    this.roundPointsFlashTarget.textContent = `+${pts}`
    this.roundPointsFlashTarget.classList.remove("hidden", "mm-pts-pop")
    void this.roundPointsFlashTarget.offsetWidth
    this.roundPointsFlashTarget.classList.add("mm-pts-pop")
    setTimeout(() => this.roundPointsFlashTarget.classList.add("hidden"), 2000)
  }

  _shakeInput() {
    const el = this.wordInputTarget
    if (!el) return
    el.classList.remove("mm-shake")
    void el.offsetWidth
    el.classList.add("mm-shake")
    el.addEventListener("animationend", () => el.classList.remove("mm-shake"), { once: true })
  }

  // ── Toast ─────────────────────────────────────────────────────────────

  showToast(msg, type = "info") {
    if (!this.toastContainerTarget) return
    const colors = {
      match: "bg-violet-700 border-violet-400",
      win:   "bg-yellow-700 border-yellow-400",
      miss:  "bg-slate-700  border-slate-500",
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
      if (remaining <= 0) {
        this.stopCountdown()
        if (this.submitBtnTarget) this.submitBtnTarget.disabled = true
      }
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
    ["phaseWaiting", "phaseTransition", "phaseTyping", "phaseReveal", "phaseGameOver"].forEach(p => {
      const el = this[`${p}Target`]
      if (el) el.classList.toggle("hidden", p !== name)
    })

    // Auto-focus the word input when the typing phase appears (helpful on mobile)
    if (name === "phaseTyping") {
      setTimeout(() => this.wordInputTarget?.focus(), 150)
    }
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
      @keyframes mm-pts-pop {
        0%   { opacity: 0; transform: scale(0.5) translateY(10px); }
        60%  { opacity: 1; transform: scale(1.3) translateY(-6px); }
        100% { opacity: 1; transform: scale(1)   translateY(0); }
      }
      @keyframes mm-shake {
        0%, 100% { transform: translateX(0); }
        20%      { transform: translateX(-8px); }
        40%      { transform: translateX(8px); }
        60%      { transform: translateX(-5px); }
        80%      { transform: translateX(5px); }
      }

      .mm-category-in  { animation: mm-category-enter 0.4s cubic-bezier(0.34, 1.56, 0.64, 1) both; }
      .mm-group-in     { animation: mm-group-enter   0.35s ease both; }
      .mm-badge-in     { animation: mm-badge-enter   0.2s  ease both; }
      .mm-toast-in     { animation: mm-toast-slide-in  0.3s ease both; }
      .mm-toast-out    { animation: mm-toast-slide-out 0.3s ease both; }
      .mm-timer-pulse  { animation: mm-timer-pulse-ring 0.6s ease infinite; }
      .mm-pts-pop      { animation: mm-pts-pop 0.5s cubic-bezier(0.34, 1.56, 0.64, 1) both; }
      .mm-shake        { animation: mm-shake 0.4s ease; }
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
