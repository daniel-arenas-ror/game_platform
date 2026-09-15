import { Controller } from "@hotwired/stimulus"
import consumer from "channels/consumer"

export default class extends Controller {
  static values  = { roomCode: String }
  static targets = [
    "phaseWaiting", "phaseShowing", "phasePicking", "phaseReveal", "phaseGameOver",
    "colorBlock", "showingTimer", "pickingTimer", "submittedList",
    "revealGrid", "roundScores", "finalLeaderboard", "roundCounter", "playAgain"
  ]

  connect() {
    this.state       = null
    this.timerHandle = null
    this.subscribe()
  }

  disconnect() {
    this.channel?.unsubscribe()
    clearInterval(this.timerHandle)
  }

  // ── ActionCable ───────────────────────────────────────────────────────────

  subscribe() {
    this.channel = consumer.subscriptions.create({
      channel:   "Games::GuessTheColorChannel",
      room_code: this.roomCodeValue,
      player_id: ""
    }, {
      connected: () => {
        console.log("[GuessTheColor Host] channel connected — starting game loop")
        this.channel.perform("start_game_loop", {})
      },
      received: (data) => this.handleMessage(data)
    })
  }

  handleMessage(data) {
    switch (data.action) {
      case "state_snapshot":   this.applySnapshot(data.state); break
      case "show_color":       this.showColor(data);           break
      case "start_picking":    this.startPicking(data);        break
      case "player_submitted": this.markSubmitted(data);       break
      case "reveal":           this.showReveal(data);          break
      case "game_over":        this.showGameOver(data);        break
      case "game_restarted":   window.location.reload();       break
      case "game_changed":     window.location.href = `/rooms/${this.roomCodeValue}`; break
    }
  }

  // ── Phase handlers ────────────────────────────────────────────────────────

  applySnapshot(state) {
    this.state = state
    // Restore correct phase if host refreshes mid-game
    switch (state?.status) {
      case "showing_color": this.showPhase("phaseShowing"); break
      case "picking":       this.showPhase("phasePicking"); break
      case "revealing":     this.showPhase("phaseReveal");  break
      case "game_over":     this.showPhase("phaseGameOver"); break
      default:              this.showPhase("phaseWaiting");
    }
  }

  showColor(data) {
    this.stopTimer()
    this.showPhase("phaseShowing")

    const { r, g, b } = data.color
    if (this.hasColorBlockTarget)
      this.colorBlockTarget.style.background = `rgb(${r},${g},${b})`

    this.updateRoundCounter(data.round, data.total_rounds)
    this.startCountdown(this.showingTimerTarget, data.duration)
  }

  startPicking(data) {
    this.stopTimer()
    this.showPhase("phasePicking")

    if (this.hasSubmittedListTarget) this.submittedListTarget.innerHTML = ""
    this.updateRoundCounter(data.round, data.total_rounds)
    this.startCountdown(this.pickingTimerTarget, data.duration)
  }

  markSubmitted(data) {
    if (!this.hasSubmittedListTarget) return
    const pill = document.createElement("span")
    pill.className = "bg-slate-700 text-slate-300 text-xs font-bold px-3 py-1 rounded-full"
    pill.textContent = data.nickname
    this.submittedListTarget.appendChild(pill)
  }

  showReveal(data) {
    this.stopTimer()
    this.showPhase("phaseReveal")
    this.updateRoundCounter(data.round, data.total_rounds)

    // ── Color blocks grid ───────────────────────────────────────────────
    if (this.hasRevealGridTarget) {
      const { r, g, b } = data.target_color
      let html = this.colorCard(`rgb(${r},${g},${b})`, "Target", true)

      Object.entries(data.picks).forEach(([playerId, pick]) => {
        const nickname = this.nicknameFor(playerId, data)
        const pr = pick.r ?? 128
        const pg = pick.g ?? 128
        const pb = pick.b ?? 128
        html += this.colorCard(`rgb(${pr},${pg},${pb})`, nickname, false)
      })

      // Players who didn't submit
      Object.keys(data.scores).forEach(playerId => {
        if (!data.picks[playerId]) {
          const nickname = this.nicknameFor(playerId, data)
          html += this.colorCard("rgb(30,30,30)", `${nickname} (no pick)`, false, true)
        }
      })

      this.revealGridTarget.innerHTML = html
    }

    // ── Round scores list ────────────────────────────────────────────────
    if (this.hasRoundScoresTarget) {
      const sorted = Object.entries(data.scores).sort(([, a], [, b]) => b - a)
      this.roundScoresTarget.innerHTML = sorted.map(([playerId, total]) => {
        const nickname   = this.nicknameFor(playerId, data)
        const roundPts   = data.round_scores[playerId] ?? 0
        return `
          <div class="flex items-center justify-between py-2 px-4 bg-slate-800 rounded-xl">
            <span class="font-bold text-white text-sm">${nickname}</span>
            <div class="text-right">
              <span class="text-yellow-400 font-mono font-black text-lg">${total}</span>
              <span class="text-slate-500 text-xs font-mono ml-2">(+${roundPts})</span>
            </div>
          </div>`
      }).join("")
    }
  }

  showGameOver(data) {
    this.stopTimer()
    this.showPhase("phaseGameOver")

    if (this.hasFinalLeaderboardTarget) {
      const sorted = Object.entries(data.scores).sort(([, a], [, b]) => b - a)
      const medals = ["🥇", "🥈", "🥉"]
      this.finalLeaderboardTarget.innerHTML = sorted.map(([playerId, score], idx) => {
        const nickname = this.nicknameFor(playerId, data)
        const medal    = medals[idx] ?? `${idx + 1}.`
        return `
          <div class="flex items-center justify-between py-2 px-4 bg-slate-800 rounded-xl
                      ${idx === 0 ? "border border-yellow-500/50" : ""}">
            <div class="flex items-center gap-3">
              <span class="text-xl">${medal}</span>
              <span class="font-bold text-white">${nickname}</span>
            </div>
            <span class="text-yellow-400 font-mono font-black text-xl">${score}</span>
          </div>`
      }).join("")
    }

    if (this.hasPlayAgainTarget && !this.playAgainTarget._wired) {
      this.playAgainTarget._wired = true
      this.playAgainTarget.addEventListener("click", () => {
        this.channel?.perform("restart_game", {})
      })
    }
  }

  // ── Helpers ───────────────────────────────────────────────────────────────

  showPhase(targetName) {
    const allPhases = ["phaseWaiting", "phaseShowing", "phasePicking", "phaseReveal", "phaseGameOver"]
    allPhases.forEach(name => {
      const el = this[`has${name.charAt(0).toUpperCase() + name.slice(1)}Target`]
        ? this[`${name}Target`]
        : null
      if (el) el.classList.toggle("hidden", name !== targetName)
    })
  }

  startCountdown(el, seconds) {
    if (!el) return
    let remaining = seconds
    el.textContent = remaining
    this.timerHandle = setInterval(() => {
      remaining--
      el.textContent = remaining > 0 ? remaining : ""
      if (remaining <= 0) this.stopTimer()
    }, 1000)
  }

  stopTimer() {
    clearInterval(this.timerHandle)
    this.timerHandle = null
  }

  updateRoundCounter(round, total) {
    if (this.hasRoundCounterTarget)
      this.roundCounterTarget.textContent = `Round ${round} of ${total}`
  }

  colorCard(bg, label, isTarget, dimmed = false) {
    const border  = isTarget ? "border-2 border-yellow-400" : "border border-slate-700"
    const opacity = dimmed ? "opacity-40" : ""
    return `
      <div class="text-center ${opacity}">
        <div class="w-28 h-28 rounded-2xl shadow-lg ${border}"
             style="background:${bg}"></div>
        <p class="text-xs font-bold mt-2 text-slate-300 max-w-[112px] truncate">${label}</p>
      </div>`
  }

  // Look up a player's nickname from the room's player list.
  // Falls back to a shortened ID if not found (e.g. mid-game reconnect).
  nicknameFor(playerId, data) {
    return data.nicknames?.[playerId] ?? `#${playerId.slice(-4)}`
  }
}
