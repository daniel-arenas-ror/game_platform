import { Controller } from "@hotwired/stimulus"
import consumer from "channels/consumer"

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
    this.updateVisibility()
    this.subscribe()
  }

  disconnect() {
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

    this.optionButtons().forEach(btn => btn.classList.replace("border-yellow-400", "border-blue-800"))
    event.currentTarget.classList.replace("border-blue-800", "border-yellow-400")

    this.optionButtons().forEach(btn => {
      btn.disabled = true
      btn.classList.add("opacity-60", "cursor-not-allowed")
    })

    if (this.hasLockedMessageTarget) this.lockedMessageTarget.classList.remove("hidden")
    if (this.hasLockLabelTarget)     this.lockLabelTarget.classList.add("hidden")

    this.channel.perform("submit_millionaire_answer", { choice: this.selectedOption })
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
      btn.classList.remove("opacity-60", "cursor-not-allowed", "border-yellow-400")
      btn.classList.add("border-blue-800")
    })
    if (this.hasLockedMessageTarget) this.lockedMessageTarget.classList.add("hidden")
    if (this.hasLockLabelTarget)     this.lockLabelTarget.classList.remove("hidden")

    // Populate question text (targets appear in both host and player sections)
    const roundLabel = `Round ${data.round} / ${data.total}`
    this.questionTextTargets.forEach(el => { el.textContent = data.text })
    this.questionMetaTargets.forEach(el => { el.textContent = roundLabel })

    const labels = [this.optionATarget, this.optionBTarget, this.optionCTarget, this.optionDTarget]
    data.options.forEach((opt, i) => { labels[i].textContent = opt.text })

    this.statusValue = this.playerIdValue === "" ? "question" : "input"
  }

  onRevealAnswer(data) {
    const { options, correct_answer_indices, round_scores, user_points, question_points, nicknames, round, total } = data

    this.revealRoundLabelTarget.textContent = `Round ${round} / ${total} — Reveal`

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
        ? `Correct! +${earned.toLocaleString()} pts`
        : "Incorrect — 0 pts"
      this.revealResultTextTarget.style.color = correct ? "#4ade80" : "#f87171"
      this.revealTotalTextTarget.textContent  = `Running total: ${myTotal.toLocaleString()} pts`
    } else {
      // ── Host view: show per-player round summary ────────────────────────
      this.revealPlayerResultTarget.classList.add("hidden")
      this.revealHostScoresTarget.classList.remove("hidden")

      this.revealHostScoresTarget.innerHTML = Object.keys(nicknames)
        .sort((a, b) => (user_points[b] || 0) - (user_points[a] || 0))
        .map(pid => {
          const name   = nicknames[pid] || pid
          const earned = round_scores[pid] || 0
          const runTotal = user_points[pid] || 0
          const scored = earned > 0

          return `
            <div class="flex items-center justify-between p-3 rounded-xl border
                        ${scored ? "border-green-700/50 bg-green-900/10" : "border-slate-800 bg-slate-900/30"}">
              <span class="font-bold text-sm ${scored ? "text-green-300" : "text-slate-500"}">${name}</span>
              <div class="text-right font-mono text-xs">
                <span class="${scored ? "text-green-400 font-black" : "text-slate-600"}">
                  ${scored ? "+" + earned.toLocaleString() : "+0"}
                </span>
                <span class="text-slate-600 ml-2">(${runTotal.toLocaleString()} total)</span>
              </div>
            </div>
          `
        }).join("")
    }

    this.statusValue = "reveal"
  }

  onShowLeaderboard(data) {
    const { leaderboard, nicknames } = data
    const medals = ["🥇", "🥈", "🥉"]

    this.leaderboardListTarget.innerHTML = Object.entries(leaderboard).map(([playerId, points], index) => {
      const name  = (nicknames && nicknames[playerId]) || `Player ${index + 1}`
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
            px-4 py-1 rounded-full text-sm">${points.toLocaleString()}</span>
        </div>
      `
    }).join("")

    this.statusValue = "leaderboard"
  }

  // ── Helpers ───────────────────────────────────────────────────────────────

  optionButtons() {
    return this.element.querySelectorAll('[data-action="click->millionaire#selectOption"]')
  }
}
