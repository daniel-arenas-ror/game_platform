import { Controller } from "@hotwired/stimulus"
import consumer from "channels/consumer"

export default class extends Controller {
  static targets = [
    "phaseWaiting", "phaseBattle", "phaseGameOver",
    "playerList", "startBtn"
  ]
  static values = { roomCode: String, gridSize: Number, subCount: Number }

  connect() {
    this.subscribe()
  }

  disconnect() {
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
    const state      = data.state || {}
    const placements = state.placements || {}
    const nicknames  = data.nicknames  || {}

    const confirmedIds = Object.entries(placements)
      .filter(([, p]) => p.confirmed)
      .map(([id]) => id)

    this.renderPlayerList(nicknames, confirmedIds)

    if (confirmedIds.length > 0 && confirmedIds.length === Object.keys(placements).length) {
      this.startBtnTarget.disabled = false
    }

    this.showPhase(state.phase === "battle" ? "battle" : "waiting")
  }

  onPlacementConfirmed(data) {
    this.renderPlayerList(data.nicknames, data.confirmed_ids)

    if (data.all_confirmed) {
      this.startBtnTarget.disabled = false
    }
  }

  // ── Channel actions ───────────────────────────────────────────────────────

  startBattle() {
    this.startBtnTarget.disabled = true
    this.channel.perform("start_battle_loop", {})
    this.showPhase("battle")
  }

  // ── UI helpers ────────────────────────────────────────────────────────────

  showPhase(name) {
    const phases = ["waiting", "battle", "gameOver"]
    phases.forEach(phase => {
      const target = this[`phase${capitalize(phase)}Target`]
      if (target) target.classList.toggle("hidden", phase !== name)
    })
  }

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
}

function capitalize(str) {
  return str.charAt(0).toUpperCase() + str.slice(1)
}
