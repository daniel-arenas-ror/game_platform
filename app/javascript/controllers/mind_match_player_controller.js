import { Controller } from "@hotwired/stimulus"
import consumer from "../channels/consumer"

export default class extends Controller {
  static values  = { roomCode: String, playerId: String }
  static targets = [
    "phaseWaiting", "phaseTyping", "phaseReveal", "phaseGameOver",
    "timerDisplay", "categoryText",
    "wordInput", "submitBtn", "inputArea", "submittedMsg",
    "revealCategory", "groupsList", "myScore",
    "finalScores"
  ]

  connect() {
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

    // Allow submit on Enter key
    this.boundKeydown = (e) => { if (e.key === "Enter") this.submitWord() }
    document.addEventListener("keydown", this.boundKeydown)
  }

  disconnect() {
    this.channel?.unsubscribe()
    clearInterval(this.countdownTimer)
    document.removeEventListener("keydown", this.boundKeydown)
  }

  // ── ActionCable callbacks ────────────────────────────────────────────

  handleMessage(data) {
    switch (data.action) {
      case "state_snapshot":   return this.onStateSnapshot(data.state)
      case "show_category":    return this.onShowCategory(data)
      case "player_submitted": return this.onPlayerSubmitted(data)
      case "reveal":           return this.onReveal(data)
      case "game_over":        return this.onGameOver(data)
      case "game_restarted":   return this.onGameRestarted(data)
    }
  }

  // ── Message handlers ─────────────────────────────────────────────────

  onStateSnapshot(state) {
    this.nicknames = state.nicknames || {}

    if (state.status === "game_over") {
      this.showPhase("phaseGameOver")
      this.renderFinalScores(state.scores || {})
    } else if (state.status === "collecting") {
      // Reconnected mid-round — show typing phase (already submitted check below)
      const alreadySubmitted = !!state.answers?.[this.playerIdValue]
      this.showPhase("phaseTyping")
      if (this.categoryTextTarget)
        this.categoryTextTarget.textContent = state.current_category || ""
      if (alreadySubmitted) this._markSubmitted()
    } else {
      this.showPhase("phaseWaiting")
    }
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
    this.startCountdown(data.duration)
  }

  onPlayerSubmitted(data) {
    // If it's this player confirming their own submit, mark submitted
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

    this.renderGroups(data.groups || [], data.round_scores || {})

    const myPts = (data.round_scores || {})[this.playerIdValue] || 0
    const total  = (data.scores || {})[this.playerIdValue] || 0
    if (this.myScoreTarget)
      this.myScoreTarget.textContent = total

    this._flashPoints(myPts)
  }

  onGameOver(data) {
    this.stopCountdown()
    this.nicknames = data.nicknames || this.nicknames
    this.showPhase("phaseGameOver")
    this.renderFinalScores(data.scores || {})
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
    if (!word) return

    this.channel.perform("submit_word", { word })
    // Optimistically mark submitted (server will confirm via player_submitted)
    this.submitted = true
    this._markSubmitted()
  }

  // ── Rendering ────────────────────────────────────────────────────────

  renderGroups(groups, roundScores) {
    if (!this.groupsListTarget) return

    const myId = this.playerIdValue
    this.groupsListTarget.innerHTML = groups.map(g => {
      const n     = g.player_ids.length
      const isMe  = g.player_ids.includes(myId)
      const pts   = n > 1 ? `+${n} pts` : "No match"
      const nicks = g.player_ids.map(id => this.esc(this.nicknames[id] || id)).join(", ")

      let color = "border-slate-600 bg-slate-800"
      if (n > 1 && isMe)  color = "border-yellow-400 bg-yellow-400/10"
      else if (n > 1)     color = "border-violet-400 bg-violet-400/10"

      return `
        <div class="border-2 ${color} rounded-2xl px-5 py-4 flex items-center justify-between gap-4">
          <div>
            <p class="text-white font-black text-lg">${this.esc(g.word)}</p>
            <p class="text-slate-400 text-xs mt-1">${nicks}</p>
          </div>
          <p class="text-sm font-bold ${n > 1 ? "text-yellow-400" : "text-slate-600"} whitespace-nowrap">${pts}</p>
        </div>`
    }).join("")
  }

  renderFinalScores(scores) {
    if (!this.finalScoresTarget) return
    const myId = this.playerIdValue

    this.finalScoresTarget.innerHTML = Object.entries(scores)
      .sort(([, a], [, b]) => b - a)
      .map(([id, pts], i) => {
        const nick   = this.esc(this.nicknames[id] || id)
        const isMe   = id === myId
        const medal  = i === 0 ? "🥇" : i === 1 ? "🥈" : i === 2 ? "🥉" : `${i + 1}.`
        const highlight = isMe ? "border border-violet-500/60 bg-violet-500/10" : "bg-slate-800"
        return `
          <div class="flex items-center justify-between px-5 py-3 ${highlight} rounded-xl">
            <span class="text-base text-white font-semibold">${medal} ${nick}${isMe ? " <span class='text-violet-400 text-xs'>(you)</span>" : ""}</span>
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

  _flashPoints(pts) {
    if (pts <= 0) return
    const el = document.createElement("p")
    el.textContent = `+${pts} pts`
    el.className = "text-yellow-400 font-black text-2xl text-center mt-2 animate-bounce"
    this.myScoreTarget?.parentElement?.appendChild(el)
    setTimeout(() => el.remove(), 2000)
  }

  // ── Timer ────────────────────────────────────────────────────────────

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
  }

  // ── Phase switch ─────────────────────────────────────────────────────

  showPhase(name) {
    const phases = ["phaseWaiting", "phaseTyping", "phaseReveal", "phaseGameOver"]
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
