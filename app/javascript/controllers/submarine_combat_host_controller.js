import { Controller } from "@hotwired/stimulus"
import consumer from "channels/consumer"

const SHIP_COLORS = [
  { fill: "#06b6d4", border: "#0891b2" },
  { fill: "#3b82f6", border: "#2563eb" },
  { fill: "#8b5cf6", border: "#7c3aed" },
  { fill: "#f59e0b", border: "#d97706" },
  { fill: "#ec4899", border: "#db2777" },
]

export default class extends Controller {
  static targets = [
    // Waiting phase
    "phaseWaiting", "playerList", "startBtn",
    // Battle phase
    "phaseBattle",
    "roundLabel", "timerDisplay", "submissionsList", "allGrids",
    // Game Over
    "phaseGameOver", "gameOverTitle", "finalScores"
  ]
  static values = { roomCode: String, gridSize: Number, subCount: Number }

  connect() {
    this.countdownTimer   = null
    this.currentNicknames = {}
    this.activeIds        = []
    this.submittedIds     = []
    this.subscribe()
  }

  disconnect() {
    this.stopCountdown()
    this.channel?.unsubscribe()
  }

  subscribe() {
    this.channel = consumer.subscriptions.create({
      channel:   "Games::SubmarineCombatChannel",
      room_code: this.roomCodeValue,
      player_id: ""
    }, {
      connected: () => console.log("[SubmarineCombat Host] connected"),
      received:  (data) => this.handleMessage(data)
    })
  }

  // ── Message handler ──────────────────────────────────────────────────────

  handleMessage(data) {
    console.log("[SubmarineCombat Host] received", data.action, data)
    switch (data.action) {
      case "state_snapshot":      this.onStateSnapshot(data);      break
      case "placement_confirmed": this.onPlacementConfirmed(data); break
      case "start_round":         this.onStartRound(data);         break
      case "shot_submitted":      this.onShotSubmitted(data);      break
      case "round_result":        this.onRoundResult(data);        break
      case "game_over":           this.onGameOver(data);           break
      case "game_restarted":      window.location.reload();        break
      case "game_changed":        window.location.href = `/rooms/${this.roomCodeValue}`; break
    }
  }

  // ── Placement phase handlers ─────────────────────────────────────────────

  onStateSnapshot(data) {
    const state      = data.state || {}
    const placements = state.placements || {}
    this.currentNicknames = data.nicknames || {}

    if (state.phase === "battle") {
      // Reconnected mid-battle — render current grid state
      this.activeIds = Object.entries(placements)
        .filter(([, p]) => !p.eliminated)
        .map(([id]) => id)
      this.showPhase("battle")
      this.renderAllGrids(placements, this.currentNicknames)
      this.roundLabelTarget.textContent = `Round ${state.round || "—"}`
    } else {
      const confirmedIds = Object.entries(placements)
        .filter(([, p]) => p.confirmed)
        .map(([id]) => id)
      this.renderPlayerList(this.currentNicknames, confirmedIds)

      if (confirmedIds.length > 0 && confirmedIds.length === Object.keys(placements).length) {
        this.startBtnTarget.disabled = false
      }
      this.showPhase("waiting")
    }
  }

  onPlacementConfirmed(data) {
    this.currentNicknames = { ...this.currentNicknames, ...data.nicknames }
    this.renderPlayerList(data.nicknames, data.confirmed_ids)
    if (data.all_confirmed) this.startBtnTarget.disabled = false
  }

  // ── Battle phase handlers ────────────────────────────────────────────────

  onStartRound(data) {
    this.stopCountdown()
    this.currentNicknames = { ...this.currentNicknames, ...data.nicknames }
    this.activeIds        = data.active_ids || []
    this.submittedIds     = []

    this.roundLabelTarget.textContent = `Round ${data.round}`
    this.renderSubmissions()

    this.showPhase("battle")
    this.startCountdown(data.duration)
  }

  onShotSubmitted(data) {
    if (!this.submittedIds.includes(data.player_id)) {
      this.submittedIds.push(data.player_id)
    }
    this.renderSubmissions()
  }

  onRoundResult(data) {
    this.stopCountdown()
    this.currentNicknames = { ...this.currentNicknames, ...data.nicknames }
    this.renderAllGrids(data.placements || {}, this.currentNicknames)

    // Show eliminations
    if ((data.eliminated || []).length > 0) {
      data.eliminated.forEach(id => {
        const nick = this.currentNicknames[id] || id.slice(-4)
        const banner = document.createElement("p")
        banner.className = "text-red-400 font-bold text-sm text-center mt-2"
        banner.textContent = `${nick} eliminated!`
        this.allGridsTarget.parentElement.appendChild(banner)
        setTimeout(() => banner.remove(), 3000)
      })
    }
  }

  onGameOver(data) {
    this.stopCountdown()
    const winnerNick = (data.nicknames || {})[data.winner_id] || "Unknown"
    this.gameOverTitleTarget.textContent = `${winnerNick} wins!`
    this.renderFinalScores(data.scores, data.nicknames)
    this.showPhase("gameOver")
  }

  // ── Channel actions ───────────────────────────────────────────────────────

  startBattle() {
    this.startBtnTarget.disabled = true
    this.channel.perform("start_battle_loop", {})
    this.showPhase("battle")
  }

  restartGame() {
    this.channel.perform("restart_game", {})
  }

  // ── Grid rendering ───────────────────────────────────────────────────────

  renderAllGrids(placements, nicknames) {
    const container = this.allGridsTarget
    container.innerHTML = ""
    const n = this.gridSizeValue

    Object.entries(placements).forEach(([playerId, placement]) => {
      const nick        = (nicknames || {})[playerId] || playerId.slice(-4)
      const eliminated  = !!placement.eliminated
      const hitCells    = placement.ships.flatMap(ship => ship.hits || [])

      // Panel wrapper
      const panel = document.createElement("div")
      panel.className = [
        "bg-slate-900 rounded-2xl p-4 border-2",
        eliminated ? "border-red-900 opacity-50" : "border-slate-700"
      ].join(" ")

      // Player name
      const nameEl = document.createElement("p")
      nameEl.className = "text-sm font-bold text-slate-300 mb-2 text-center"
      nameEl.textContent = eliminated ? `${nick} (out)` : nick
      panel.appendChild(nameEl)

      // Mini-grid
      const grid = document.createElement("div")
      grid.className   = "grid gap-[2px]"
      grid.style.gridTemplateColumns = `repeat(${n}, 1fr)`

      for (let r = 0; r < n; r++) {
        for (let c = 0; c < n; c++) {
          const shipIdx = placement.ships.findIndex(ship =>
            ship.cells.some(([sr, sc]) => sr === r && sc === c)
          )
          const isHit = hitCells.some(([hr, hc]) => hr === r && hc === c)

          const cell = document.createElement("div")
          cell.className = "aspect-square rounded-[2px]"

          if (isHit) {
            cell.style.backgroundColor = "#dc2626"
          } else if (shipIdx >= 0) {
            const color = SHIP_COLORS[shipIdx % SHIP_COLORS.length]
            cell.style.backgroundColor = color.fill + "99"
          } else {
            cell.style.backgroundColor = "#0f172a"
          }

          grid.appendChild(cell)
        }
      }

      panel.appendChild(grid)
      container.appendChild(panel)
    })
  }

  // ── Submissions tracker ──────────────────────────────────────────────────

  renderSubmissions() {
    const list = this.submissionsListTarget
    list.innerHTML = ""
    this.activeIds.forEach(id => {
      const submitted = this.submittedIds.includes(id)
      const nick      = this.currentNicknames[id] || id.slice(-4)
      const badge     = document.createElement("div")
      badge.className = [
        "px-3 py-1 rounded-full text-xs font-bold border transition-all",
        submitted
          ? "bg-green-500/20 border-green-500 text-green-400"
          : "bg-slate-800 border-slate-600 text-slate-500"
      ].join(" ")
      badge.textContent = submitted ? `${nick} fired` : nick
      list.appendChild(badge)
    })
  }

  // ── Placement player list ────────────────────────────────────────────────

  renderPlayerList(nicknames, confirmedIds) {
    const list = this.playerListTarget
    list.innerHTML = ""
    Object.entries(nicknames || {}).forEach(([id, nick]) => {
      const confirmed = (confirmedIds || []).includes(id)
      const badge     = document.createElement("div")
      badge.dataset.playerId = id
      badge.className = [
        "px-5 py-3 rounded-2xl text-base font-bold border-2 transition-all",
        confirmed
          ? "bg-cyan-500/20 border-cyan-500 text-cyan-300"
          : "bg-slate-800 border-slate-600 text-slate-400"
      ].join(" ")
      badge.textContent = confirmed ? `${nick} — Ready` : nick
      list.appendChild(badge)
    })
  }

  // ── Final scores ─────────────────────────────────────────────────────────

  renderFinalScores(scores, nicknames) {
    const container = this.finalScoresTarget
    container.innerHTML = ""
    const sorted = Object.entries(scores || {}).sort(([, a], [, b]) => b - a)
    sorted.forEach(([id, pts], i) => {
      const nick = (nicknames || {})[id] || id.slice(-4)
      const row  = document.createElement("div")
      row.className = "flex items-center justify-between px-4 py-3 bg-slate-800/60 rounded-xl"
      row.innerHTML = `
        <span class="text-slate-200 font-bold">${i + 1}. ${nick}</span>
        <span class="text-cyan-400 font-black tabular-nums">${pts} hits</span>
      `
      container.appendChild(row)
    })
  }

  // ── Countdown ────────────────────────────────────────────────────────────

  startCountdown(seconds) {
    let remaining = seconds
    this.timerDisplayTarget.textContent = remaining

    this.countdownTimer = setInterval(() => {
      remaining -= 1
      if (remaining >= 0) {
        this.timerDisplayTarget.textContent = remaining
        if (remaining <= 5) {
          this.timerDisplayTarget.style.borderColor = "#ef4444"
          this.timerDisplayTarget.style.color       = "#ef4444"
        } else {
          this.timerDisplayTarget.style.borderColor = ""
          this.timerDisplayTarget.style.color       = ""
        }
      } else {
        this.stopCountdown()
      }
    }, 1000)
  }

  stopCountdown() {
    if (this.countdownTimer) {
      clearInterval(this.countdownTimer)
      this.countdownTimer = null
    }
  }

  // ── Phase toggle ─────────────────────────────────────────────────────────

  showPhase(name) {
    const phases = ["waiting", "battle", "gameOver"]
    phases.forEach(phase => {
      const el = this[`phase${capitalize(phase)}Target`]
      if (el) el.classList.toggle("hidden", phase !== name)
    })
  }
}

function capitalize(str) {
  return str.charAt(0).toUpperCase() + str.slice(1)
}
