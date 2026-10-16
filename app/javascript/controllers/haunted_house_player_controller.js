import { Controller } from "@hotwired/stimulus"
import consumer from "channels/consumer"
import { t } from "controllers/shared/i18n"
import { celebrateWin } from "controllers/shared/celebration"
import { ROLE_ICON, roleName, placeName, startCountdown, stopCountdown, injectStyles } from "controllers/haunted_house/common"

const PLACES = ["attic", "basement", "kitchen", "library", "bedroom", "garden"]

// A phone. The server sends this player's own view of every phase ("state": the public state plus
// its role, and for a ghost the other ghosts and their picks, for the Medium their checks), so the
// controller redraws from it. Phones play no sounds, so nobody's role gives itself away.
export default class extends Controller {
  static values  = { roomCode: String, playerId: String }
  static targets = [
    "status", "countdown", "roleButton", "roleCard", "roleLabel", "roleIcon", "roleName", "roleDesc", "roleExtra",
    "panel", "phaseGameOver", "gameOverIcon", "gameOverTitle", "gameOverHint"
  ]

  connect() {
    injectStyles()
    this.state     = null
    this.nicknames = {}
    this.keepAwake()

    this.channel = consumer.subscriptions.create(
      { channel: "Games::HauntedHouseChannel", room_code: this.roomCodeValue, player_id: this.playerIdValue },
      {
        rejected: () => window.location.reload(), // removed from the room → the server sends us to /join
        received: (data) => this.handleMessage(data)
      }
    )
  }

  disconnect() {
    stopCountdown(this.countdownTarget)
    document.removeEventListener("visibilitychange", this.onVisible)
    this.wakeLock?.release().catch(() => {})
    this.channel?.unsubscribe()
  }

  handleMessage(data) {
    if (data.action === "game_restarted") return window.location.reload()
    if (data.action === "game_changed") return (window.location.href = `/rooms/${this.roomCodeValue}`)
    if (!this.state && data.action !== "state") return // nothing to update before the first state

    switch (data.action) {
      case "state":          this.onState(data); break
      case "ghost_picks":    this.state.ghost_picks = data.ghost_picks; this.render(); break
      case "medium_result":  this.onMediumResult(data); break
      case "hidden":         this.state.my_hide = data.place; this.render(); break
      case "voted":          this.state.my_vote = data.target_id; this.render(); break
      case "player_left":    this.channel.perform("sync", {}); break
    }
  }

  // ── Actions ───────────────────────────────────────────────────────────────

  toggleRole() {
    const show = this.roleCardTarget.classList.contains("hidden")
    this.roleCardTarget.classList.toggle("hidden", !show)
  }

  pick(event) {
    const id = event.currentTarget.dataset.id
    switch (this.move) {
      case "ghost":  this.channel.perform("ghost_pick", { target_id: id }); break
      case "medium": this.lock(event.currentTarget); this.channel.perform("medium_check", { target_id: id }); break
      case "vote":   this.lock(event.currentTarget); this.channel.perform("vote", { target_id: id }); break
    }
  }

  hide(event) {
    this.lock(event.currentTarget)
    this.channel.perform("hide", { place: event.currentTarget.dataset.place })
  }

  // ── State ─────────────────────────────────────────────────────────────────

  onState({ state, nicknames }) {
    const previous = this.state?.phase
    this.state     = state
    this.nicknames = nicknames || {}
    this.fillRoleCard()

    // The role card shows on its own during the roles phase, then only when asked for.
    if (state.phase !== previous) this.roleCardTarget.classList.toggle("hidden", !["waiting", "roles"].includes(state.phase))
    this.roleButtonTarget.classList.toggle("hidden", !state.my_role || state.phase === "game_over")

    if (state.phase === "game_over") stopCountdown(this.countdownTarget)
    else startCountdown(this.countdownTarget, state.seconds_left)

    this.render()
    if (state.phase === "game_over" && previous !== "game_over") this.showGameOver()
  }

  onMediumResult({ target_id, ghost }) {
    this.state.medium_checks = { ...(this.state.medium_checks || {}), [this.state.night]: { target: target_id, ghost } }
    this.render()
  }

  render() {
    const s = this.state
    if (!s) return
    this.move = null
    this.statusTarget.textContent = s.night > 0 ? t("haunted_house.night", { night: s.night }) : ""

    if (s.phase === "game_over") return this.panel()
    if (!s.alive_me && s.phase !== "waiting" && s.phase !== "roles") return this.renderOut()

    switch (s.phase) {
      case "night":      return this.renderNight()
      case "discussion": return this.panel(this.message("🗣️", t("haunted_house.talk")), this.checksList())
      case "vote":       return this.renderVote()
      case "morning":
      case "verdict":    return this.panel(this.message("📺", this.lookTv))
      default:           return this.panel()
    }
  }

  renderNight() {
    const s = this.state
    switch (s.my_role) {
      case "ghost": {
        this.move = "ghost"
        const mine     = s.ghost_picks?.[this.playerIdValue]
        const team     = s.ghost_team || []
        const targets  = s.alive.filter(id => !team.includes(id))
        const partners = Object.entries(s.ghost_picks || {}).filter(([ghost]) => ghost !== this.playerIdValue)
        const notes    = partners.map(([ghost, target]) => t("haunted_house.partner_pick", { name: this.name(ghost), target: this.name(target) }))
        return this.panel(this.title(t("haunted_house.pick_victim")), this.playerList(targets, mine), this.notes(notes))
      }
      case "medium": {
        const check = s.medium_checks?.[s.night]
        if (check) return this.panel(this.result(check), this.checksList())
        this.move = "medium"
        const targets = s.alive.filter(id => id !== this.playerIdValue)
        return this.panel(this.title(t("haunted_house.pick_check")), this.playerList(targets), this.checksList())
      }
      default: {
        if (s.my_hide) {
          return this.panel(this.message(t(`haunted_house.place_icons.${s.my_hide}`),
                                         t("haunted_house.hiding_in", { place: placeName(s.my_hide).toLowerCase() }),
                                         t("haunted_house.done_wait")))
        }
        return this.panel(this.title(t("haunted_house.pick_place")), this.placeGrid())
      }
    }
  }

  renderVote() {
    const s = this.state
    if (s.my_vote) return this.panel(this.message("🗳️", t("haunted_house.you_voted", { name: this.name(s.my_vote) })))

    this.move = "vote"
    const targets = s.alive.filter(id => id !== this.playerIdValue)
    return this.panel(this.title(t("haunted_house.vote_for")), this.playerList(targets), this.checksList())
  }

  renderOut() {
    const s      = this.state
    const me     = (s.out || []).find(o => o.id === this.playerIdValue)
    const reason = me?.how === "voted" ? t("haunted_house.you_voted_out") : t("haunted_house.scared_you")
    this.panel(this.message("👻", reason, this.element.dataset.outHint || ""))
  }

  fillRoleCard() {
    const s = this.state
    if (!s.my_role) return
    this.roleLabelTarget.textContent = t("haunted_house.you_are")
    this.roleIconTarget.textContent  = ROLE_ICON[s.my_role]
    this.roleNameTarget.textContent  = roleName(s.my_role)
    this.roleDescTarget.textContent  = t(`haunted_house.role_desc.${s.my_role}`)
    const others = (s.ghost_team || []).filter(id => id !== this.playerIdValue)
    this.roleExtraTarget.textContent = others.length ? t("haunted_house.other_ghosts", { names: others.map(id => this.name(id)).join(", ") }) : ""
  }

  showGameOver() {
    const s       = this.state
    const ghostsWon = s.winner === "ghosts"
    const won     = (s.winners || []).includes(this.playerIdValue)
    this.gameOverIconTarget.textContent  = ghostsWon ? "👻" : "🎃"
    this.gameOverTitleTarget.textContent = t(won ? "haunted_house.you_win" : "haunted_house.you_lose")
    this.gameOverHintTarget.textContent  = t(ghostsWon ? "haunted_house.ghosts_win" : "haunted_house.guests_win")
    this.phaseGameOverTarget.classList.remove("hidden")
    if (won) celebrateWin(this.gameOverTitleTarget)
  }

  // ── Building blocks (player text goes in as text, never HTML) ─────────────

  panel(...children) {
    this.panelTarget.replaceChildren(...children.filter(Boolean))
  }

  title(text) {
    const p = document.createElement("p")
    p.className = "text-center font-black text-2xl mb-5 text-balance"
    p.textContent = text
    return p
  }

  message(icon, text, hint = "") {
    const box = document.createElement("div")
    box.className = "text-center hh-appear"
    const i = document.createElement("p")
    i.className = "text-6xl mb-3"
    i.textContent = icon
    const p = document.createElement("p")
    p.className = "font-black text-2xl text-balance"
    p.textContent = text
    box.append(i, p)
    if (hint) {
      const h = document.createElement("p")
      h.className = "text-slate-400 text-sm mt-2"
      h.textContent = hint
      box.append(h)
    }
    return box
  }

  // Big buttons, one per player. `selected` stays highlighted (a ghost may change their pick).
  playerList(ids, selected = null) {
    const list = document.createElement("div")
    list.className = "grid gap-3"
    ids.forEach(id => {
      const button = document.createElement("button")
      button.type = "button"
      button.dataset.id = id
      button.dataset.action = "haunted-house-player#pick"
      button.className = `w-full rounded-2xl border-2 px-5 py-4 text-left text-xl font-black transition-transform active:scale-95 cursor-pointer
        ${id === selected ? "border-orange-400 bg-orange-500/20 text-orange-200" : "border-slate-700 bg-slate-900/80"}`
      button.textContent = this.name(id)
      list.append(button)
    })
    return list
  }

  placeGrid() {
    const grid = document.createElement("div")
    grid.className = "grid grid-cols-2 gap-3"
    PLACES.forEach(place => {
      const button = document.createElement("button")
      button.type = "button"
      button.dataset.place = place
      button.dataset.action = "haunted-house-player#hide"
      button.className = "flex flex-col items-center gap-1 rounded-2xl border-2 border-slate-700 bg-slate-900/80 py-5 font-black text-lg transition-transform active:scale-95 cursor-pointer"
      const icon = document.createElement("span")
      icon.className = "text-4xl"
      icon.textContent = t(`haunted_house.place_icons.${place}`)
      const label = document.createElement("span")
      label.textContent = placeName(place)
      button.append(icon, label)
      grid.append(button)
    })
    return grid
  }

  result({ target, ghost }) {
    return this.message(ghost ? "👻" : "✅",
                        t(ghost ? "haunted_house.check_result_ghost" : "haunted_house.check_result_safe", { name: this.name(target) }),
                        t("haunted_house.done_wait"))
  }

  // The Medium's earlier checks, as a reminder by day.
  checksList() {
    const checks = Object.entries(this.state.medium_checks || {})
    if (this.state.my_role !== "medium" || checks.length === 0) return null

    const box = document.createElement("div")
    box.className = "mt-6 rounded-2xl border border-slate-700 bg-slate-900/80 p-4"
    const heading = document.createElement("p")
    heading.className = "text-slate-400 text-xs uppercase tracking-widest font-mono mb-2"
    heading.textContent = t("haunted_house.checks_so_far")
    box.append(heading)
    checks.forEach(([night, check]) => {
      const p = document.createElement("p")
      p.className = check.ghost ? "font-bold text-orange-300" : "text-slate-300"
      p.textContent = `${t("haunted_house.night", { night })}: ${t(check.ghost ? "haunted_house.check_result_ghost" : "haunted_house.check_result_safe", { name: this.name(check.target) })}`
      box.append(p)
    })
    return box
  }

  notes(lines) {
    if (lines.length === 0) return null
    const box = document.createElement("div")
    box.className = "mt-4 space-y-1 text-center text-orange-200 text-sm font-bold"
    lines.forEach(line => {
      const p = document.createElement("p")
      p.textContent = `👻 ${line}`
      box.append(p)
    })
    return box
  }

  lock(button) {
    this.panelTarget.querySelectorAll("button").forEach(b => { b.disabled = true; b.classList.add("opacity-40") })
    button.classList.remove("opacity-40")
    button.classList.add("border-orange-400")
  }

  get lookTv() {
    return this.element.dataset.lookTv || "📺"
  }

  name(id) {
    return this.nicknames[id] || "?"
  }

  // Keep the screen on: the night and the vote need the phone ready.
  async keepAwake() {
    if (!("wakeLock" in navigator)) return
    const request = async () => { try { this.wakeLock = await navigator.wakeLock.request("screen") } catch {} }
    this.onVisible = () => { if (document.visibilityState === "visible") request() }
    document.addEventListener("visibilitychange", this.onVisible)
    request()
  }
}
