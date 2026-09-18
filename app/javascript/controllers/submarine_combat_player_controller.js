import { Controller } from "@hotwired/stimulus"
import consumer from "channels/consumer"

const SHIP_COLORS = [
  { fill: "#06b6d4", border: "#0891b2" },  // cyan
  { fill: "#3b82f6", border: "#2563eb" },  // blue
  { fill: "#8b5cf6", border: "#7c3aed" },  // violet
  { fill: "#f59e0b", border: "#d97706" },  // amber
  { fill: "#ec4899", border: "#db2777" },  // pink
]

export default class extends Controller {
  static targets = [
    // Placement phase
    "phasePlacement", "grid", "shipInfo", "rotateBtn", "confirmBtn",
    // Waiting phase
    "phaseWaiting", "waitingList",
    // Battle phase
    "phaseBattle",
    "roundLabel", "timerDisplay", "submissionsList", "shotStatus",
    "attackGrid", "fireBtn",
    "defenseGrid",
    // Spectator / Game over
    "phaseSpectator",
    "phaseGameOver", "gameOverTitle", "finalScores"
  ]
  static values = { roomCode: String, playerId: String, gridSize: Number, subCount: Number }

  connect() {
    // Placement state
    this.ships           = []
    this.selectedShipIdx = null
    this.confirmed       = false
    // Battle state
    this.myShots         = []   // [{ row, col, hit: bool }]
    this.selectedAttack  = null // { row, col }
    this.shotSubmitted   = false
    this.myPlacement     = null // current placement data from server
    this.countdownTimer  = null

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
      player_id: this.playerIdValue
    }, {
      connected: () => console.log("[SubmarineCombat Player] connected"),
      received:  (data) => this.handleMessage(data)
    })
  }

  // ── Message handler ──────────────────────────────────────────────────────

  handleMessage(data) {
    console.log("[SubmarineCombat Player] received", data.action, data)
    switch (data.action) {
      case "state_snapshot":      this.onStateSnapshot(data);      break
      case "placement_shuffled":  this.onPlacementShuffled(data);  break
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
    const myPlacement = placements[this.playerIdValue]
    if (!myPlacement) return

    this.ships        = myPlacement.ships.map(s => this.annotateShip(s))
    this.confirmed    = !!myPlacement.confirmed
    this.myPlacement  = myPlacement

    if (data.nicknames) {
      const confirmedIds = Object.entries(placements)
        .filter(([, p]) => p.confirmed)
        .map(([id]) => id)
      this.renderWaitingList(confirmedIds, data.nicknames)
    }

    if (state.phase === "battle") {
      // Reconnected mid-battle — restore shot history from state
      this.myShots = this.restoreShotHistory(state)
      this.showPhase("battle")
      this.buildAttackGrid()
      this.buildDefenseGrid(myPlacement)
      this.shotStatusTarget.textContent = "Waiting for round to begin..."
      this.fireBtnTarget.disabled = true
    } else if (this.confirmed) {
      this.showPhase("waiting")
    } else {
      this.showPhase("placement")
      this.buildGrid()
      this.renderShipInfo()
    }
  }

  onPlacementShuffled(data) {
    this.ships           = data.ships.map(s => this.annotateShip(s))
    this.selectedShipIdx = null
    this.buildGrid()
    this.renderShipInfo()
    this.confirmBtnTarget.disabled = false
  }

  onPlacementConfirmed(data) {
    this.renderWaitingList(data.confirmed_ids, data.nicknames)
    if (data.player_id === this.playerIdValue) {
      this.confirmed = true
      this.showPhase("waiting")
    }
  }

  // ── Battle phase handlers ────────────────────────────────────────────────

  onStartRound(data) {
    this.stopCountdown()
    this.selectedAttack = null
    this.shotSubmitted  = false

    this.roundLabelTarget.textContent  = `Round ${data.round}`
    this.shotStatusTarget.textContent  = "Tap a cell to pick your target"
    this.fireBtnTarget.disabled        = true

    this.renderSubmissions(data.active_ids, [], data.nicknames)
    this.buildAttackGrid()

    this.showPhase("battle")
    this.startCountdown(data.duration)
  }

  onShotSubmitted(data) {
    // Track who has submitted so we can update the badge list
    const current = Array.from(
      this.submissionsListTarget.querySelectorAll("[data-submitted='true']")
    ).map(el => el.dataset.playerId)

    if (!current.includes(data.player_id)) current.push(data.player_id)

    // Re-render submissions with the same active list but updated submitted set
    const allBadges = Array.from(this.submissionsListTarget.children)
    const activeIds = allBadges.map(el => el.dataset.playerId)
    const nicknames = Object.fromEntries(
      allBadges.map(el => [el.dataset.playerId, el.dataset.nickname])
    )
    this.renderSubmissions(activeIds, current, nicknames)
  }

  onRoundResult(data) {
    this.stopCountdown()

    // Record my shot result
    const myPick = (data.picks || {})[this.playerIdValue]
    if (myPick) {
      const [row, col] = myPick
      const myHits     = (data.hits || {})[this.playerIdValue] || []
      const isHit      = myHits.some(([, hr, hc]) => hr === row && hc === col)
      // Replace or add entry for this round's shot
      this.myShots = this.myShots.filter(s => !(s.row === row && s.col === col))
      this.myShots.push({ row, col, hit: isHit })
    }

    // Update my placement to reflect hits I've received
    const myPlacement = (data.placements || {})[this.playerIdValue]
    if (myPlacement) {
      this.myPlacement = myPlacement
      this.buildDefenseGrid(myPlacement)
    }

    // Rebuild attack grid to show result
    this.buildAttackGrid()

    // Show result message
    if (myPick) {
      const [row, col] = myPick
      const myHits = (data.hits || {})[this.playerIdValue] || []
      const hitCount = myHits.length
      if (hitCount > 0) {
        this.shotStatusTarget.textContent = `Hit! You struck ${hitCount} ship cell${hitCount > 1 ? "s" : ""}`
      } else {
        this.shotStatusTarget.textContent = "Miss — no ships at that coordinate"
      }
    } else {
      this.shotStatusTarget.textContent = "No shot submitted this round"
    }

    // Check if I was eliminated
    if ((data.eliminated || []).includes(this.playerIdValue)) {
      setTimeout(() => this.showPhase("spectator"), 1500)
    }
  }

  onGameOver(data) {
    this.stopCountdown()

    const isWinner = data.winner_id === this.playerIdValue
    this.gameOverTitleTarget.textContent = isWinner ? "Victory!" : "Defeated"
    this.gameOverTitleTarget.className   = isWinner
      ? "text-3xl font-black text-yellow-400 mb-8"
      : "text-3xl font-black text-slate-400 mb-8"

    this.renderFinalScores(data.scores, data.nicknames, this.finalScoresTarget)

    this.showPhase("gameOver")
  }

  // ── Placement grid ───────────────────────────────────────────────────────

  buildGrid() {
    const container = this.gridTarget
    container.innerHTML = ""
    const n = this.gridSizeValue
    container.style.gridTemplateColumns = `repeat(${n}, 1fr)`

    for (let r = 0; r < n; r++) {
      for (let c = 0; c < n; c++) {
        const shipIdx  = this.shipIndexAt(r, c)
        const selected = shipIdx >= 0 && shipIdx === this.selectedShipIdx
        const cell     = document.createElement("div")

        cell.className = "aspect-square rounded-sm border cursor-pointer transition-colors"

        if (shipIdx < 0) {
          cell.style.backgroundColor = "#1e293b"
          cell.style.borderColor     = "#334155"
        } else {
          const color = SHIP_COLORS[shipIdx % SHIP_COLORS.length]
          cell.style.backgroundColor = selected ? color.fill : color.fill + "88"
          cell.style.borderColor     = selected ? "#ffffff" : color.border
          cell.style.borderWidth     = "2px"
        }

        cell.addEventListener("click", () => this.tapCell(r, c, shipIdx))
        container.appendChild(cell)
      }
    }
  }

  shipIndexAt(r, c) {
    return this.ships.findIndex(ship =>
      ship.cells.some(([sr, sc]) => sr === r && sc === c)
    )
  }

  tapCell(r, c, shipIdx) {
    if (this.confirmed) return

    if (this.selectedShipIdx === null) {
      if (shipIdx >= 0) {
        this.selectedShipIdx = shipIdx
        this.buildGrid()
        this.renderShipInfo()
      }
    } else if (shipIdx === this.selectedShipIdx) {
      this.selectedShipIdx = null
      this.buildGrid()
      this.renderShipInfo()
    } else {
      this.tryMoveShip(this.selectedShipIdx, r, c)
    }
  }

  tryMoveShip(idx, anchorRow, anchorCol) {
    const ship  = this.ships[idx]
    const n     = this.gridSizeValue
    const newCells = ship._orientation === "h"
      ? Array.from({ length: ship.size }, (_, i) => [anchorRow, anchorCol + i])
      : Array.from({ length: ship.size }, (_, i) => [anchorRow + i, anchorCol])

    if (newCells.some(([r, c]) => r < 0 || r >= n || c < 0 || c >= n)) return

    const otherCells = this.ships.filter((_, i) => i !== idx).flatMap(s => s.cells)
    if (newCells.some(([r, c]) => otherCells.some(([or, oc]) => or === r && oc === c))) return

    this.ships[idx]      = { ...ship, cells: newCells }
    this.selectedShipIdx = null
    this.buildGrid()
    this.renderShipInfo()
  }

  rotateShip() {
    if (this.selectedShipIdx === null) return
    const idx            = this.selectedShipIdx
    const ship           = this.ships[idx]
    const n              = this.gridSizeValue
    const newOrientation = ship._orientation === "h" ? "v" : "h"

    let [ar, ac] = ship.cells[0]
    if (newOrientation === "h") ac = Math.min(ac, n - ship.size)
    else                        ar = Math.min(ar, n - ship.size)

    const newCells = newOrientation === "h"
      ? Array.from({ length: ship.size }, (_, i) => [ar, ac + i])
      : Array.from({ length: ship.size }, (_, i) => [ar + i, ac])

    const otherCells = this.ships.filter((_, i) => i !== idx).flatMap(s => s.cells)
    if (newCells.some(([r, c]) => otherCells.some(([or, oc]) => or === r && oc === c))) return

    this.ships[idx] = { ...ship, cells: newCells, _orientation: newOrientation }
    this.buildGrid()
    this.renderShipInfo()
  }

  // ── Battle grid ──────────────────────────────────────────────────────────

  buildAttackGrid() {
    const container = this.attackGridTarget
    container.innerHTML = ""
    const n = this.gridSizeValue
    container.style.gridTemplateColumns = `repeat(${n}, 1fr)`

    for (let r = 0; r < n; r++) {
      for (let c = 0; c < n; c++) {
        const shot     = this.myShots.find(s => s.row === r && s.col === c)
        const selected = this.selectedAttack &&
                         this.selectedAttack.row === r &&
                         this.selectedAttack.col === c

        const cell = document.createElement("div")
        cell.className = "aspect-square rounded-sm border-2 transition-colors"

        if (shot) {
          // Already fired at this cell
          cell.style.backgroundColor = shot.hit ? "#dc2626" : "#1e293b"
          cell.style.borderColor     = shot.hit ? "#991b1b" : "#334155"
          cell.style.cursor          = "default"
          if (shot.hit) {
            cell.innerHTML = '<div class="w-full h-full flex items-center justify-center text-white text-[10px] font-black">X</div>'
          }
        } else if (selected) {
          cell.style.backgroundColor = "#0891b2"
          cell.style.borderColor     = "#06b6d4"
          cell.style.cursor          = "pointer"
          cell.addEventListener("click", () => this.selectAttackCell(r, c))
        } else {
          cell.style.backgroundColor = "#1e293b"
          cell.style.borderColor     = "#334155"
          if (!this.shotSubmitted) {
            cell.style.cursor = "pointer"
            cell.addEventListener("click", () => this.selectAttackCell(r, c))
          }
        }

        container.appendChild(cell)
      }
    }
  }

  buildDefenseGrid(placement) {
    const container = this.defenseGridTarget
    container.innerHTML = ""
    const n = this.gridSizeValue
    container.style.gridTemplateColumns = `repeat(${n}, 1fr)`

    // Build a hit-cell lookup
    const hitCells = placement.ships.flatMap(ship => ship.hits || [])

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
          cell.innerHTML = '<div class="w-full h-full flex items-center justify-center text-white text-[8px] font-black">X</div>'
        } else if (shipIdx >= 0) {
          const color = SHIP_COLORS[shipIdx % SHIP_COLORS.length]
          cell.style.backgroundColor = color.fill + "99"
        } else {
          cell.style.backgroundColor = "#0f172a"
        }

        container.appendChild(cell)
      }
    }
  }

  selectAttackCell(r, c) {
    if (this.shotSubmitted) return
    const already = this.myShots.find(s => s.row === r && s.col === c)
    if (already) return

    this.selectedAttack = { row: r, col: c }
    this.fireBtnTarget.disabled = false
    this.shotStatusTarget.textContent = `Selected: row ${r + 1}, col ${c + 1}`
    this.buildAttackGrid()
  }

  // ── Channel actions ───────────────────────────────────────────────────────

  shuffleAll() {
    this.channel.perform("shuffle_placement", {})
  }

  confirmPlacement() {
    if (this.confirmed) return
    const ships = this.ships.map(({ cells, size, hits }) => ({ cells, size, hits }))
    this.channel.perform("confirm_placement", { ships })
    this.confirmBtnTarget.disabled = true
  }

  submitShot() {
    if (!this.selectedAttack || this.shotSubmitted) return
    this.channel.perform("submit_shot", this.selectedAttack)
    this.shotSubmitted          = true
    this.fireBtnTarget.disabled = true
    this.shotStatusTarget.textContent = "Shot submitted — waiting for results..."
  }

  // ── UI helpers ────────────────────────────────────────────────────────────

  showPhase(name) {
    const phases = ["placement", "waiting", "battle", "spectator", "gameOver"]
    phases.forEach(phase => {
      const el = this[`phase${capitalize(phase)}Target`]
      if (el) el.classList.toggle("hidden", phase !== name)
    })
  }

  renderShipInfo() {
    const info = this.shipInfoTarget
    if (this.selectedShipIdx === null) {
      info.innerHTML = '<p class="text-slate-600 text-xs">Tap a ship to select it</p>'
      this.rotateBtnTarget.disabled = true
    } else {
      const ship  = this.ships[this.selectedShipIdx]
      const color = SHIP_COLORS[this.selectedShipIdx % SHIP_COLORS.length]
      const dir   = ship._orientation === "h" ? "Horizontal" : "Vertical"
      info.innerHTML = `<p class="text-sm font-bold" style="color:${color.fill}">
        Ship selected &mdash; size ${ship.size} &middot; ${dir} &mdash; tap a cell to move
      </p>`
      this.rotateBtnTarget.disabled = false
    }
  }

  renderWaitingList(confirmedIds, nicknames) {
    const list = this.waitingListTarget
    list.innerHTML = ""
    Object.entries(nicknames || {}).forEach(([id, nick]) => {
      const confirmed = (confirmedIds || []).includes(id)
      const badge     = document.createElement("div")
      badge.className = [
        "px-4 py-2 rounded-full text-sm font-bold border-2 transition-all",
        confirmed
          ? "bg-cyan-500/20 border-cyan-500 text-cyan-300"
          : "bg-slate-800 border-slate-600 text-slate-500"
      ].join(" ")
      badge.textContent = confirmed ? `${nick} — Ready` : nick
      list.appendChild(badge)
    })
  }

  renderSubmissions(activeIds, submittedIds, nicknames) {
    const list = this.submissionsListTarget
    list.innerHTML = ""
    activeIds.forEach(id => {
      const submitted = submittedIds.includes(id)
      const nick      = (nicknames || {})[id] || id.slice(-4)
      const badge     = document.createElement("div")
      badge.dataset.playerId  = id
      badge.dataset.nickname  = nick
      badge.dataset.submitted = submitted ? "true" : "false"
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

  renderFinalScores(scores, nicknames, container) {
    container.innerHTML = ""
    const sorted = Object.entries(scores || {}).sort(([, a], [, b]) => b - a)
    sorted.forEach(([id, pts], i) => {
      const nick = (nicknames || {})[id] || id.slice(-4)
      const row  = document.createElement("div")
      row.className = "flex items-center justify-between px-4 py-2 bg-slate-800/60 rounded-xl"
      row.innerHTML = `
        <span class="text-slate-300 font-bold text-sm">${i + 1}. ${nick}</span>
        <span class="text-cyan-400 font-black tabular-nums">${pts} hits</span>
      `
      container.appendChild(row)
    })
  }

  startCountdown(seconds) {
    let remaining = seconds
    this.timerDisplayTarget.textContent = remaining

    this.countdownTimer = setInterval(() => {
      remaining -= 1
      if (remaining >= 0) {
        this.timerDisplayTarget.textContent = remaining
        // Turn red in final 5 seconds
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

  // Rebuild shot history from game_state on reconnect mid-battle
  restoreShotHistory(state) {
    const myRawShots = (state.shots || {})[this.playerIdValue] || []
    return myRawShots.map(([row, col]) => {
      const isHit = Object.entries(state.placements || {}).some(([targetId, placement]) => {
        if (targetId === this.playerIdValue) return false
        return placement.ships.some(ship =>
          (ship.hits || []).some(([hr, hc]) => hr === row && hc === col)
        )
      })
      return { row, col, hit: isHit }
    })
  }

  annotateShip(ship) {
    const cells      = ship.cells || []
    const horizontal = cells.length < 2 || cells[0][0] === cells[1][0]
    return { ...ship, _orientation: horizontal ? "h" : "v" }
  }
}

function capitalize(str) {
  return str.charAt(0).toUpperCase() + str.slice(1)
}
