import { Controller } from "@hotwired/stimulus"
import consumer from "channels/consumer"
import { celebrateWin, isTopScore } from "controllers/shared/celebration"
import { t, num } from "controllers/shared/i18n"
import { escapeHtml } from "controllers/shared/html"

export default class extends Controller {
  static targets = [
    "loading",
    "question",
    "input",
    "reveal",
    "leaderboard",
    // question / input shared
    "questionText",
    "questionMeta",
    "optionA", "optionB", "optionC", "optionD",
    "lockedMessage",
    "lockLabel",
    "countdown",          // array — host + player
    // reveal section
    "revealRoundLabel",
    "revealOption",       // array — 4 elements
    "revealOptionText",   // array — 4 elements
    "revealOptionIcon",   // array — 4 elements
    "revealPlayerResult",
    "revealResultText",
    "revealTotalText",
    "revealHostScores",
    // leaderboard
    "leaderboardList"
  ]

  static values = { status: String, roomCode: String, playerId: String }

  connect() {
    this.answered       = false
    this.selectedOption = null
    this.timerHandle    = null
    this.clickingSound  = new Audio("/games/sounds/clicking.mp3")
    this.chooseSound    = new Audio("/games/sounds/choose.mp3")
    this.clickingSound.loop = true
    this.updateVisibility()
    this.subscribe()
  }

  disconnect() {
    this.winSound?.pause()
    this.stopCountdown()
    this.channel?.unsubscribe()
  }

  statusValueChanged() {
    this.updateVisibility()
  }

  updateVisibility() {
    const s = this.statusValue
    this.loadingTarget.classList.toggle("hidden",     s !== "loading")
    this.questionTarget.classList.toggle("hidden",    s !== "question")
    this.inputTarget.classList.toggle("hidden",       s !== "input")
    this.revealTarget.classList.toggle("hidden",      s !== "reveal")
    this.leaderboardTarget.classList.toggle("hidden", s !== "leaderboard")
  }

  // ── Player taps an answer ─────────────────────────────────────────────────

  selectOption(event) {
    if (this.answered) return
    this.answered       = true
    this.selectedOption = parseInt(event.currentTarget.dataset.option, 10)
    this.chooseSound.currentTime = 0
    this.chooseSound.play().catch(() => {}) // ignore autoplay blocks

    this.optionButtons().forEach(btn => btn.classList.replace("border-yellow-400", "border-blue-800"))
    event.currentTarget.classList.replace("border-blue-800", "border-yellow-400")

    // The picked answer stays bright; the others fade.
    this.optionButtons().forEach(btn => {
      btn.disabled = true
      btn.classList.add("cursor-not-allowed")
      if (btn !== event.currentTarget) btn.classList.add("opacity-40")
    })

    if (this.hasLockedMessageTarget) this.lockedMessageTarget.classList.remove("hidden")
    if (this.hasLockLabelTarget)     this.lockLabelTarget.classList.add("hidden")

    this.channel.perform("submit_millionaire_answer", { choice: this.selectedOption })
  }

  // ── Host: Play Again ──────────────────────────────────────────────────────

  restartGame(event) {
    event.currentTarget.disabled = true
    this.channel.perform("restart_game", {})
  }

  // ── Subscribe ─────────────────────────────────────────────────────────────

  subscribe() {
    this.channel = consumer.subscriptions.create({
      channel:   "Games::MillionaireChannel",
      room_code: this.roomCodeValue,
      player_id: this.playerIdValue
    }, {
      connected: () => {
        if (this.statusValue === "loading" && this.playerIdValue === "") {
          this.channel.perform("start_game_loop", {})
        }
      },
      rejected: () => window.location.reload(),   // removed after a long disconnect → server sends us to /join
      received: (data) => this.handleMessage(data)
    })
  }

  handleMessage(data) {
    switch (data.action) {
      case "send_question":    this.onSendQuestion(data);   break
      case "reveal_answer":    this.onRevealAnswer(data);   break
      case "show_leaderboard": this.onShowLeaderboard(data); break
      case "player_presence":  break
      case "game_restarted":   window.location.reload();    break
      case "game_changed":     window.location.href = `/rooms/${this.roomCodeValue}`; break
      default: console.warn("[Millionaire] unhandled action:", data.action)
    }
  }

  // ── Message handlers ──────────────────────────────────────────────────────

  onSendQuestion(data) {
    // Reset round state
    this.answered       = false
    this.selectedOption = null

    this.optionButtons().forEach(btn => {
      btn.disabled = false
      btn.classList.remove("opacity-40", "cursor-not-allowed", "border-yellow-400")
      btn.classList.add("border-blue-800")
    })
    if (this.hasLockedMessageTarget) this.lockedMessageTarget.classList.add("hidden")
    if (this.hasLockLabelTarget)     this.lockLabelTarget.classList.remove("hidden")

    // Populate question text (targets appear in both host and player sections)
    const roundLabel = t("how_want_be_billionare.round", { round: data.round, total: data.total })
    this.questionTextTargets.forEach(el => { el.textContent = data.text })
    this.questionMetaTargets.forEach(el => { el.textContent = roundLabel })

    const labels = [this.optionATarget, this.optionBTarget, this.optionCTarget, this.optionDTarget]
    data.options.forEach((opt, i) => { labels[i].textContent = opt.text })

    this.statusValue = this.playerIdValue === "" ? "question" : "input"
    this.startCountdown(data.duration)
  }

  onRevealAnswer(data) {
    this.stopCountdown()
    const { options, correct_answer_indices, round_scores, user_points, question_points, nicknames, round, total } = data

    this.revealRoundLabelTarget.textContent = t("how_want_be_billionare.round_reveal", { round, total })

    // Colour each answer tile
    this.revealOptionTargets.forEach((el, i) => {
      this.revealOptionTextTargets[i].textContent = options[i]?.text || ""

      const isCorrect = correct_answer_indices.includes(i)
      const isMyWrong = i === this.selectedOption && !isCorrect

      el.style.borderColor       = isCorrect ? "#4ade80" : (isMyWrong ? "#f87171" : "#334155")
      el.style.backgroundColor   = isCorrect ? "rgba(21,128,61,0.15)" : (isMyWrong ? "rgba(153,27,27,0.15)" : "transparent")
      el.style.opacity           = (!isCorrect && !isMyWrong) ? "0.35" : "1"

      const icon = this.revealOptionIconTargets[i]
      if (isCorrect) {
        icon.textContent  = "✓"
        icon.style.color  = "#4ade80"
      } else if (isMyWrong) {
        icon.textContent  = "✗"
        icon.style.color  = "#f87171"
      } else {
        icon.textContent  = ""
      }
    })

    if (this.playerIdValue !== "") {
      // ── Player view: show their own result ─────────────────────────────
      const myId    = this.playerIdValue
      const earned  = round_scores[myId] || 0
      const myTotal = user_points[myId]  || 0
      const correct = earned > 0

      this.revealPlayerResultTarget.classList.remove("hidden")
      this.revealHostScoresTarget.classList.add("hidden")

      this.revealResultTextTarget.textContent = correct
        ? t("how_want_be_billionare.correct", { points: num(earned) })
        : t("how_want_be_billionare.incorrect")
      this.revealResultTextTarget.style.color = correct ? "#4ade80" : "#f87171"
      this.revealTotalTextTarget.textContent  = t("how_want_be_billionare.running_total", { points: num(myTotal) })
    } else {
      // ── Host view: show per-player round summary ────────────────────────
      this.revealPlayerResultTarget.classList.add("hidden")
      this.revealHostScoresTarget.classList.remove("hidden")

      this.revealHostScoresTarget.innerHTML = Object.keys(nicknames)
        .sort((a, b) => (user_points[b] || 0) - (user_points[a] || 0))
        .map(pid => {
          const name   = escapeHtml(nicknames[pid] || pid)
          const earned = round_scores[pid] || 0
          const runTotal = user_points[pid] || 0
          const scored = earned > 0

          return `
            <div class="flex items-center justify-between p-3 rounded-xl border
                        ${scored ? "border-green-700/50 bg-green-900/10" : "border-slate-800 bg-slate-900/30"}">
              <span class="font-bold text-sm ${scored ? "text-green-300" : "text-slate-500"}">${name}</span>
              <div class="text-right font-mono text-xs">
                <span class="${scored ? "text-green-400 font-black" : "text-slate-600"}">
                  ${scored ? "+" + num(earned) : "+0"}
                </span>
                <span class="text-slate-600 ml-2">${t("how_want_be_billionare.total", { points: num(runTotal) })}</span>
              </div>
            </div>
          `
        }).join("")
    }

    this.statusValue = "reveal"
  }

  onShowLeaderboard(data) {
    this.stopCountdown()
    if (!this.playerIdValue) {
      this.winSound = new Audio("/games/sounds/Triumphant_win.mp3")
      this.winSound.play().catch(() => {}) // ignore autoplay blocks
    }
    const { leaderboard, nicknames } = data
    const medals = ["🥇", "🥈", "🥉"]

    this.leaderboardListTarget.innerHTML = Object.entries(leaderboard).map(([playerId, points], index) => {
      const name  = escapeHtml((nicknames && nicknames[playerId]) || t("how_want_be_billionare.player", { n: index + 1 }))
      const isTop = index === 0
      const medal = medals[index] || `#${index + 1}`

      return `
        <div class="flex items-center justify-between
                    ${isTop
                      ? "bg-gradient-to-r from-yellow-500/20 via-slate-900 to-slate-900 border border-yellow-500/40 shadow-lg shadow-yellow-500/5"
                      : "bg-slate-900/80 border border-blue-900/50"}
                    p-4 rounded-2xl">
          <div class="flex items-center space-x-4">
            <span class="text-xl font-black ${isTop ? "text-yellow-400" : "text-slate-500"}">${medal}</span>
            <span class="font-bold ${isTop ? "text-slate-100" : "text-slate-300"}">${name}</span>
          </div>
          <span class="font-mono ${isTop
            ? "bg-yellow-400 text-slate-950 font-black"
            : "bg-blue-950 border border-blue-800 text-blue-400 font-bold"}
            px-4 py-1 rounded-full text-sm">${num(points)}</span>
        </div>
      `
    }).join("")

    this.statusValue = "leaderboard"
    if (this.playerIdValue && isTopScore(leaderboard, this.playerIdValue)) celebrateWin()
  }

  // ── Countdown ─────────────────────────────────────────────────────────────

  startCountdown(seconds) {
    this.stopCountdown()
    if (!seconds) return

    let remaining = seconds
    this.renderCountdown(remaining)

    // Host only: looping tension sound while players answer
    if (this.playerIdValue === "") {
      this.clickingSound.currentTime = 0
      this.clickingSound.play().catch(() => {}) // ignore autoplay blocks
    }

    this.timerHandle = setInterval(() => {
      remaining -= 1
      this.renderCountdown(Math.max(remaining, 0))
      if (remaining <= 0) this.stopCountdown()
    }, 1000)
  }

  stopCountdown() {
    clearInterval(this.timerHandle)
    this.timerHandle = null
    this.clickingSound?.pause()
  }

  renderCountdown(remaining) {
    this.countdownTargets.forEach(el => {
      el.textContent = remaining
      el.classList.toggle("text-yellow-400", remaining > 5)
      el.classList.toggle("text-red-500",    remaining <= 5)
    })
  }

  // ── Helpers ───────────────────────────────────────────────────────────────

  optionButtons() {
    return this.element.querySelectorAll('[data-action="click->millionaire#selectOption"]')
  }
}
