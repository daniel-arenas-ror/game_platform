import { Controller } from "@hotwired/stimulus"
import consumer from "channels/consumer"

// Color palette for ships (by ship index)
const SHIP_COLORS = [
  { fill: "#06b6d4", border: "#0891b2" },  // cyan
  { fill: "#3b82f6", border: "#2563eb" },  // blue
  { fill: "#8b5cf6", border: "#7c3aed" },  // violet
  { fill: "#f59e0b", border: "#d97706" },  // amber
  { fill: "#ec4899", border: "#db2777" },  // pink
]

export default class extends Controller {
  static targets = [
    "phasePlacement", "phaseWaiting", "phaseBattle", "phaseSpectator", "phaseGameOver",
    "grid", "shipInfo", "rotateBtn", "confirmBtn", "waitingList"
  ]
  static values = { roomCode: String, playerId: String, gridSize: Number, subCount: Number }

  connect() {
    this.ships            = []   // [{ cells, size, hits, _orientation }, ...]
    this.selectedShipIdx  = null
    this.confirmed        = false
    this.subscribe()
  }

  disconnect() {
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
      case "start_round":         /* Phase 3 */ break
      case "shot_submitted":      /* Phase 3 */ break
      case "round_result":        /* Phase 3 */ break
      case "game_over":           /* Phase 3 */ break
      case "game_restarted":      window.location.reload(); break
      case "game_changed":        window.location.href = `/rooms/${this.roomCodeValue}`; break
    }
  }

  // ── State handlers ───────────────────────────────────────────────────────

  onStateSnapshot(data) {
    const state       = data.state || {}
    const placements  = state.placements || {}
    const myPlacement = placements[this.playerIdValue]
    if (!myPlacement) return

    this.ships     = myPlacement.ships.map(s => this.annotateShip(s))
    this.confirmed = !!myPlacement.confirmed

    // Pre-populate the waiting list with whatever is already confirmed
    if (data.nicknames) {
      const confirmedIds = Object.entries(placements)
        .filter(([, p]) => p.confirmed)
        .map(([id]) => id)
      this.renderWaitingList(confirmedIds, data.nicknames)
    }

    if (this.confirmed || state.phase === "battle") {
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

    // Switch this player to waiting phase when their own confirmation comes back
    if (data.player_id === this.playerIdValue) {
      this.confirmed = true
      this.showPhase("waiting")
    }
  }

  // ── Grid ─────────────────────────────────────────────────────────────────

  buildGrid() {
    const container = this.gridTarget
    container.innerHTML = ""
    const n = this.gridSizeValue
    container.style.gridTemplateColumns = `repeat(${n}, 1fr)`

    for (let r = 0; r < n; r++) {
      for (let c = 0; c < n; c++) {
        const shipIdx  = this.shipIndexAt(r, c)
        const selected = shipIdx >= 0 && shipIdx === this.selectedShipIdx

        const cell = document.createElement("div")
        cell.className = "aspect-square rounded-sm border cursor-pointer transition-colors"

        if (shipIdx < 0) {
          cell.style.backgroundColor = "#1e293b"   // slate-800
          cell.style.borderColor      = "#334155"   // slate-700
          cell.addEventListener("mouseenter", () => {
            cell.style.backgroundColor = "#334155"
          })
          cell.addEventListener("mouseleave", () => {
            cell.style.backgroundColor = "#1e293b"
          })
        } else {
          const color = SHIP_COLORS[shipIdx % SHIP_COLORS.length]
          cell.style.backgroundColor = selected ? color.fill : color.fill + "88"
          cell.style.borderColor      = selected ? "#ffffff" : color.border
          cell.style.borderWidth      = "2px"
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

  // ── Touch / tap logic ────────────────────────────────────────────────────

  tapCell(r, c, shipIdx) {
    if (this.confirmed) return

    if (this.selectedShipIdx === null) {
      // Select the tapped ship
      if (shipIdx >= 0) {
        this.selectedShipIdx = shipIdx
        this.buildGrid()
        this.renderShipInfo()
      }
    } else if (shipIdx === this.selectedShipIdx) {
      // Tap the same ship → deselect
      this.selectedShipIdx = null
      this.buildGrid()
      this.renderShipInfo()
    } else {
      // Move selected ship so its anchor lands on (r, c)
      this.tryMoveShip(this.selectedShipIdx, r, c)
    }
  }

  tryMoveShip(idx, anchorRow, anchorCol) {
    const ship        = this.ships[idx]
    const n           = this.gridSizeValue
    const orientation = ship._orientation

    const newCells = orientation === "h"
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

    // Anchor at first cell, clamp so the ship stays in-bounds after rotation
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

  // ── Channel actions ───────────────────────────────────────────────────────

  shuffleAll() {
    this.channel.perform("shuffle_placement", {})
  }

  confirmPlacement() {
    if (this.confirmed) return
    // Strip _orientation before sending — server doesn't need it
    const ships = this.ships.map(({ cells, size, hits }) => ({ cells, size, hits }))
    this.channel.perform("confirm_placement", { ships })
    this.confirmBtnTarget.disabled = true
  }

  // ── UI helpers ────────────────────────────────────────────────────────────

  showPhase(name) {
    const phases = ["placement", "waiting", "battle", "spectator", "gameOver"]
    phases.forEach(phase => {
      const target = this[`phase${capitalize(phase)}Target`]
      if (target) target.classList.toggle("hidden", phase !== name)
    })
  }

  renderShipInfo() {
    const info = this.shipInfoTarget
    if (this.selectedShipIdx === null) {
      info.innerHTML = '<p class="text-slate-600 text-xs">Tap a ship to select it</p>'
      this.rotateBtnTarget.disabled = true
    } else {
      const ship      = this.ships[this.selectedShipIdx]
      const color     = SHIP_COLORS[this.selectedShipIdx % SHIP_COLORS.length]
      const direction = ship._orientation === "h" ? "Horizontal" : "Vertical"
      info.innerHTML  = `<p class="text-sm font-bold" style="color:${color.fill}">
        Ship selected &mdash; size ${ship.size} &middot; ${direction} &mdash; tap a cell to move
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

  // Infers horizontal/vertical orientation from cell layout
  annotateShip(ship) {
    const cells       = ship.cells || []
    const horizontal  = cells.length < 2 || cells[0][0] === cells[1][0]
    return { ...ship, _orientation: horizontal ? "h" : "v" }
  }
}

function capitalize(str) {
  return str.charAt(0).toUpperCase() + str.slice(1)
}
