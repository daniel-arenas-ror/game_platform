import { Controller } from "@hotwired/stimulus"
import consumer from "channels/consumer"

export default class extends Controller {
  static targets = [
    "loading",
    "question",
    "input",
    "leaderboard",
    "questionText",
    "questionMeta",
    "optionA", "optionB", "optionC", "optionD",
    "lockedMessage",
    "leaderboardList"
  ]

  static values = { status: String, roomCode: String, playerId: String }

  connect() {
    this.answered = false
    this.updateVisibility()
    this.subscribe()
  }

  disconnect() {
    this.channel?.unsubscribe()
  }

  // Fires automatically whenever statusValue changes
  statusValueChanged() {
    this.updateVisibility()
  }

  updateVisibility() {
    const s = this.statusValue
    this.loadingTarget.classList.toggle("hidden",    s !== "loading")
    this.questionTarget.classList.toggle("hidden",   s !== "question")
    this.inputTarget.classList.toggle("hidden",      s !== "input")
    this.leaderboardTarget.classList.toggle("hidden", s !== "leaderboard")
  }

  // Player taps an answer button
  selectOption(event) {
    if (this.answered) return

    this.answered = true

    const selectedOption = parseInt(event.currentTarget.dataset.option, 10)

    // Highlight selected, dim others
    this.optionButtons().forEach(btn => btn.classList.replace("border-yellow-400", "border-blue-800"))
    event.currentTarget.classList.replace("border-blue-800", "border-yellow-400")

    // Disable all buttons so the player can't change their answer
    this.optionButtons().forEach(btn => {
      btn.disabled = true
      btn.classList.add("opacity-60", "cursor-not-allowed")
    })

    // Show "locked in" confirmation
    if (this.hasLockedMessageTarget) {
      this.lockedMessageTarget.classList.remove("hidden")
    }

    this.channel.perform("submit_millionaire_answer", { choice: selectedOption })
  }

  subscribe() {
    this.channel = consumer.subscriptions.create({
      channel:   "Games::MillionaireChannel",
      room_code: this.roomCodeValue,
      player_id: this.playerIdValue
    }, {
      connected: () => {
        // Host (no player_id) starts the game loop
        if (this.statusValue === "loading" && this.playerIdValue === "") {
          this.channel.perform("start_game_loop", {})
        }
      },
      received: (data) => this.handleMessage(data)
    })
  }

  handleMessage(data) {
    switch (data.action) {
      case "send_question":   this.onSendQuestion(data);   break
      case "show_leaderboard": this.onShowLeaderboard(data); break
      case "player_presence": break   // handled silently
      case "game_restarted":  window.location.reload();    break
      case "game_changed":    window.location.href = `/rooms/${this.roomCodeValue}`; break
      default:
        console.warn("[Millionaire] unhandled action:", data.action)
    }
  }

  onSendQuestion(data) {
    // Reset answer lock for the new round
    this.answered = false
    this.optionButtons().forEach(btn => {
      btn.disabled = false
      btn.classList.remove("opacity-60", "cursor-not-allowed", "border-yellow-400")
      btn.classList.add("border-blue-800")
    })
    if (this.hasLockedMessageTarget) {
      this.lockedMessageTarget.classList.add("hidden")
    }

    // Populate question and options (targets appear in both host and player sections)
    const roundLabel = `Round ${data.round} / ${data.total}`
    this.questionTextTargets.forEach(el => { el.textContent = data.text })
    this.questionMetaTargets.forEach(el => { el.textContent = roundLabel })

    const labels = [this.optionATarget, this.optionBTarget, this.optionCTarget, this.optionDTarget]
    data.options.forEach((opt, i) => { labels[i].textContent = opt.text })

    // Host sees the question panel; players see the input panel
    this.statusValue = this.playerIdValue === "" ? "question" : "input"
  }

  onShowLeaderboard(data) {
    const { leaderboard, nicknames } = data

    const medals = ["🥇", "🥈", "🥉"]

    this.leaderboardListTarget.innerHTML = Object.entries(leaderboard).map(([playerId, points], index) => {
      const name   = (nicknames && nicknames[playerId]) || `Player ${index + 1}`
      const isTop  = index === 0
      const medal  = medals[index] || `#${index + 1}`

      return `
        <div class="flex items-center justify-between
                    ${isTop
                      ? 'bg-gradient-to-r from-yellow-500/20 via-slate-900 to-slate-900 border border-yellow-500/40 shadow-lg shadow-yellow-500/5'
                      : 'bg-slate-900/80 border border-blue-900/50'}
                    p-4 rounded-2xl">
          <div class="flex items-center space-x-4">
            <span class="text-xl font-black ${isTop ? 'text-yellow-400' : 'text-slate-500'}">${medal}</span>
            <span class="font-bold ${isTop ? 'text-slate-100' : 'text-slate-300'}">${name}</span>
          </div>
          <span class="font-mono ${isTop
            ? 'bg-yellow-400 text-slate-950 font-black'
            : 'bg-blue-950 border border-blue-800 text-blue-400 font-bold'}
            px-4 py-1 rounded-full text-sm">${points.toLocaleString()}</span>
        </div>
      `
    }).join("")

    this.statusValue = "leaderboard"
  }

  // ── Helpers ──────────────────────────────────────────────────────────────

  optionButtons() {
    return this.element.querySelectorAll('[data-action="click->millionaire#selectOption"]')
  }
}
