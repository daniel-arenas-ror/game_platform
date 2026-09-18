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
    "roundLabel", "timerDisplay", "submissionsList",
    "playerBoards",
    // Game Over
    "phaseGameOver", "gameOverTitle", "finalScores",
    // Polish
    "toastContainer"
  ]
  static values = { roomCode: String, gridSize: Number, subCount: Number }

  connect() {
    this.countdownTimer   = null
    this.currentNicknames = {}
    this.activeIds        = []
    this.submittedIds     = []
    this.currentScores    = {}
    // { playerId: { "row,col": { row, col, hit: bool } } } — per-player attack history
    this.playerShotHistory = {}
    this.injectStyles()
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
      // Reconnected mid-battle — reconstruct fired-coord history from game_state.shots
      this.activeIds     = Object.entries(placements).filter(([, p]) => !p.eliminated).map(([id]) => id)
      this.currentScores = state.scores || {}

      // Reconstruct per-player attack history from game_state.shots
      Object.entries(state.shots || {}).forEach(([shooterId, coordList]) => {
        this.playerShotHistory[shooterId] = {}
        coordList.forEach(([row, col]) => {
          const key   = `${row},${col}`
          const isHit = Object.entries(placements).some(([targetId, placement]) =>
            targetId !== shooterId &&
            placement.ships.some(ship =>
              (ship.hits || []).some(([hr, hc]) => hr === row && hc === col)
            )
          )
          this.playerShotHistory[shooterId][key] = { row, col, hit: isHit }
        })
      })

      this.roundLabelTarget.textContent = `Round ${state.round || "—"}`
      this.showPhase("battle")
      this.renderPlayerBoards(placements)
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

    // Refresh aggregate board and player status at the start of each round
    // (placements may have changed if someone was eliminated last round)
    // We don't have placements here, but we can refresh the grid from allFiredCoords
    // and re-render player status on round_result when placements arrive.

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
    const placements = data.placements || {}

    // Accumulate this round's shots into per-player attack history
    this.currentScores = data.scores || {}
    Object.entries(data.picks || {}).forEach(([shooterId, pick]) => {
      if (!pick) return
      const [row, col] = pick
      const key        = `${row},${col}`
      if (!this.playerShotHistory[shooterId]) this.playerShotHistory[shooterId] = {}
      if (!this.playerShotHistory[shooterId][key]) {
        // Hit = this shooter's pick appears in their hits list for this round
        const myHits = (data.hits || {})[shooterId] || []
        const isHit  = myHits.some(([, hr, hc]) => hr === row && hc === col)
        this.playerShotHistory[shooterId][key] = { row, col, hit: isHit }
      }
    })

    this.renderPlayerBoards(placements)

    // Sunk ship toasts
    Object.entries(data.sunk_ships || {}).forEach(([targetId, shipIndices]) => {
      const targetNick = this.currentNicknames[targetId] || targetId.slice(-4)
      shipIndices.forEach(() => this.showToast(`${targetNick}'s ship sunk!`, "sunk"))
    })

    // Elimination toasts
    ;(data.eliminated || []).forEach(id => {
      const nick = this.currentNicknames[id] || id.slice(-4)
      this.showToast(`${nick} eliminated!`, "elim")
    })
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

  // One panel per player showing THAT PLAYER'S OWN attack history:
  //   red  = they fired there and hit someone's ship
  //   grey = they fired there but missed everyone
  //   dark = they haven't fired there yet
  renderPlayerBoards(placements) {
    const container   = this.playerBoardsTarget
    container.innerHTML = ""
    const n           = this.gridSizeValue
    const playerCount = Object.keys(placements).length

    const cols = playerCount === 1 ? 1 : playerCount <= 4 ? 2 : 3
    container.style.gridTemplateColumns = `repeat(${cols}, 1fr)`

    const gap        = 24
    const padding    = 32
    const maxTotal   = Math.min(window.innerWidth - 48, 896)
    const panelWidth = (maxTotal - gap * (cols - 1)) / cols
    const cellPx     = Math.max(8, Math.floor((panelWidth - padding) / n))

    Object.entries(placements).forEach(([playerId, placement]) => {
      const nick       = (this.currentNicknames || {})[playerId] || playerId.slice(-4)
      const eliminated = !!placement.eliminated
      const pts        = (this.currentScores   || {})[playerId] ?? 0
      const history    = this.playerShotHistory[playerId] || {}

      const panel = document.createElement("div")
      panel.className = [
        "bg-slate-900 rounded-2xl p-4 border-2",
        eliminated ? "border-red-900/50 opacity-60" : "border-slate-700"
      ].join(" ")

      const header = document.createElement("div")
      header.className = "flex items-center justify-between mb-3"
      header.innerHTML = `
        <span class="font-bold text-sm ${eliminated ? "text-red-400" : "text-slate-200"}">
          ${nick}${eliminated ? " (out)" : ""}
        </span>
        <span class="font-mono text-xs text-cyan-400">${pts} hits</span>
      `
      panel.appendChild(header)

      const grid = document.createElement("div")
      grid.className = "grid gap-[2px] mx-auto"
      grid.style.gridTemplateColumns = `repeat(${n}, ${cellPx}px)`

      for (let r = 0; r < n; r++) {
        for (let c = 0; c < n; c++) {
          const shot = history[`${r},${c}`]  // undefined if not yet fired by this player
          const cell = document.createElement("div")
          cell.style.width  = `${cellPx}px`
          cell.style.height = `${cellPx}px`
          cell.className    = "rounded-[2px]"

          if (!shot) {
            // This player hasn't targeted this coordinate yet
            cell.style.backgroundColor = "#0f172a"
            cell.style.border          = "1px solid #1e293b"
          } else if (shot.hit) {
            // They fired here and hit at least one opponent's ship
            cell.style.backgroundColor = "#dc2626"
          } else {
            // They fired here but no one had a ship there
            cell.style.backgroundColor = "#475569"
          }

          grid.appendChild(cell)
        }
      }

      panel.appendChild(grid)
      container.appendChild(panel)
    })
  }

  // ── Phase 5 polish ───────────────────────────────────────────────────────

  injectStyles() {
    if (document.getElementById("submarine-combat-styles")) return
    const style = document.createElement("style")
    style.id    = "submarine-combat-styles"
    style.textContent = `
      @keyframes sub-hit {
        0%   { transform: scale(1.8); opacity: 0; }
        60%  { transform: scale(0.9); }
        100% { transform: scale(1);   opacity: 1; }
      }
      @keyframes sub-toast-in {
        from { transform: translateY(12px); opacity: 0; }
        to   { transform: translateY(0);    opacity: 1; }
      }
      @keyframes sub-toast-out {
        from { opacity: 1; }
        to   { opacity: 0; transform: translateY(-8px); }
      }
    `
    document.head.appendChild(style)
  }

  showToast(message, type = "info") {
    if (!this.hasToastContainerTarget) return
    const COLORS = {
      sunk: { bg: "#d97706", border: "#92400e" },
      elim: { bg: "#7c3aed", border: "#5b21b6" },
      info: { bg: "#0891b2", border: "#0e7490" },
    }
    const c     = COLORS[type] || COLORS.info
    const toast = document.createElement("div")
    toast.style.cssText = `
      padding: 10px 20px;
      border-radius: 12px;
      font-weight: 700;
      font-size: 14px;
      letter-spacing: 0.04em;
      border: 2px solid ${c.border};
      background: ${c.bg};
      color: #fff;
      white-space: nowrap;
      animation: sub-toast-in 0.25s ease forwards;
    `
    toast.textContent = message
    this.toastContainerTarget.appendChild(toast)

    setTimeout(() => {
      toast.style.animation = "sub-toast-out 0.25s ease forwards"
      setTimeout(() => toast.remove(), 260)
    }, 3200)
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
