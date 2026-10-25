import { Controller } from "@hotwired/stimulus"
import consumer from "channels/consumer"
import { t } from "controllers/shared/i18n"
import { avatar } from "controllers/shared/avatar"
import { confetti } from "controllers/shared/celebration"
import { ROLE_ICON, roleName, placeName, startCountdown, stopCountdown, injectStyles, Sounds } from "controllers/haunted_house/common"

// The TV. The server sends the whole public state on every phase change ("state"), so this
// controller just redraws from it. It never gets anyone's role while the game is on.
export default class extends Controller {
  static values  = { roomCode: String }
  static targets = [
    "nightLabel", "icon", "headline", "subline", "tally", "progress", "countdown", "skipButton",
    "alive", "out", "outBox", "soundButton",
    "phaseGameOver", "gameOverIcon", "gameOverTitle", "gameOverHint", "finalRoles"
  ]

  connect() {
    injectStyles()
    this.sounds    = new Sounds()
    this.state     = null
    this.nicknames = {}
    this.acted     = []
    this.soundLabel = this.soundButtonTarget.textContent.trim().replace(/^\S+\s*/, "")
    this.unlockSound = () => this.sounds.unlock()
    document.addEventListener("pointerdown", this.unlockSound)

    this.channel = consumer.subscriptions.create(
      { channel: "Games::HauntedHouseChannel", room_code: this.roomCodeValue, player_id: "" },
      {
        connected: () => this.channel.perform("start_game_loop", {}),
        received:  (data) => this.handleMessage(data)
      }
    )
  }

  disconnect() {
    document.removeEventListener("pointerdown", this.unlockSound)
    stopCountdown(this.countdownTarget)
    this.sounds.close()
    this.channel?.unsubscribe()
  }

  handleMessage(data) {
    switch (data.action) {
      case "state":          this.onState(data); break
      case "acted":          this.acted = data.acted || []; this.renderProgress(); this.renderAlive(); break
      case "player_left":    this.channel.perform("sync", {}); break
      case "game_restarted": window.location.reload(); break
      case "game_changed":   window.location.href = `/rooms/${this.roomCodeValue}`; break
      case "game_error":     this.headlineTarget.textContent = t("haunted_house.error"); break
    }
  }

  // ── Actions ───────────────────────────────────────────────────────────────

  skip() {
    this.skipButtonTarget.disabled = true
    this.channel.perform("skip_discussion", {})
  }

  restart(event) {
    event.currentTarget.disabled = true
    this.channel.perform("restart_game", {})
  }

  toggleSound() {
    const on = this.sounds.toggle()
    this.soundButtonTarget.setAttribute("aria-pressed", String(on))
    this.soundButtonTarget.textContent = `${on ? "🔊" : "🔇"} ${this.soundLabel}`
    this.soundButtonTarget.classList.toggle("opacity-50", !on)
  }

  // ── State ─────────────────────────────────────────────────────────────────

  onState({ state, nicknames }) {
    const previous = this.state?.phase
    this.state     = state
    this.nicknames = nicknames || {}
    this.acted     = state.acted || []

    this.nightLabelTarget.textContent = state.night > 0 ? ` · ${t("haunted_house.night", { night: state.night })}` : ""
    this.element.classList.toggle("hh-day", ["morning", "discussion", "vote", "verdict"].includes(state.phase))
    this.tallyTarget.classList.add("hidden")
    this.skipButtonTarget.classList.add("hidden")
    this.progressTarget.textContent = ""
    this.iconTarget.classList.remove("hh-shake")

    if (state.phase !== "night") this.sounds.stopNight()
    const changed = previous !== state.phase

    switch (state.phase) {
      case "waiting":
      case "roles":      this.showRoles(); break
      case "night":      this.showNight(changed); break
      case "morning":    this.showMorning(changed); break
      case "discussion": this.showDiscussion(); break
      case "vote":       this.showVote(changed); break
      case "verdict":    this.showVerdict(); break
      case "game_over":  this.showGameOver(changed); break
    }

    if (state.phase === "game_over") stopCountdown(this.countdownTarget)
    else startCountdown(this.countdownTarget, state.seconds_left)
    this.renderAlive()
    this.renderOut()
  }

  showRoles() {
    this.setStory("🏚️", t("haunted_house.check_phone"), t("haunted_house.ghost_total", { count: this.state.ghost_total || 1 }))
  }

  showNight(changed) {
    this.setStory("🌙", t("haunted_house.night_title"), t("haunted_house.night_hint"))
    this.renderProgress()
    if (changed) this.sounds.startNight()
  }

  showMorning(changed) {
    const victim = this.state.victim
    if (!victim) {
      this.setStory("🌅", t("haunted_house.nobody_scared"), t("haunted_house.nobody_scared_hint"))
      return
    }

    const out  = (this.state.out || []).find(o => o.id === victim.id)
    const hint = [
      victim.place ? t("haunted_house.found_in", { place: placeName(victim.place).toLowerCase() }) : "",
      out?.role ? t("haunted_house.they_were", { role: roleName(out.role) }) : ""
    ].join(" ").trim()
    this.setStory("😱", t("haunted_house.scared_out", { name: this.name(victim.id) }), hint)
    this.iconTarget.classList.add("hh-shake")
    if (changed) this.sounds.scream()
  }

  showDiscussion() {
    this.setStory("🗣️", t("haunted_house.discuss_title"), t("haunted_house.discuss_hint"))
    this.skipButtonTarget.disabled = false
    this.skipButtonTarget.classList.remove("hidden")
  }

  showVote(changed) {
    this.setStory("🗳️", t("haunted_house.vote_title"), t("haunted_house.vote_hint"))
    this.renderProgress()
    if (changed) this.sounds.drumroll(2)
  }

  showVerdict() {
    const verdict = this.state.verdict || {}
    const tally   = verdict.tally || {}
    const out     = verdict.out
    const entry   = (this.state.out || []).find(o => o.id === out)

    if (out) {
      this.setStory("🚪", t("haunted_house.voted_out", { name: this.name(out) }),
                    entry?.role ? t("haunted_house.they_were", { role: roleName(entry.role) }) : "")
    } else {
      this.setStory("🤝", Object.keys(tally).length ? t("haunted_house.tie") : t("haunted_house.no_votes"), "")
    }
    this.renderTally(tally, out)
  }

  showGameOver(changed) {
    const ghostsWon = this.state.winner === "ghosts"
    this.gameOverIconTarget.textContent  = ghostsWon ? "👻" : "🎃"
    this.gameOverTitleTarget.textContent = t(ghostsWon ? "haunted_house.ghosts_win" : "haunted_house.guests_win")
    this.gameOverHintTarget.textContent  = t(ghostsWon ? "haunted_house.ghosts_win_hint" : "haunted_house.guests_win_hint")

    const winners = new Set(this.state.winners || [])
    const roles   = this.state.roles || {}
    this.finalRolesTarget.replaceChildren(...Object.keys(this.nicknames).map(id => {
      const li = document.createElement("li")
      li.className = `flex items-center gap-3 rounded-2xl border px-4 py-3 ${winners.has(id) ? "border-orange-400/60 bg-orange-500/10" : "border-slate-700 bg-slate-900"}`
      const icon = document.createElement("span")
      icon.className = "text-3xl"
      icon.textContent = ROLE_ICON[roles[id]] || "❔"
      const text = document.createElement("span")
      text.className = "min-w-0"
      const name = document.createElement("span")
      name.className = "block truncate font-black text-lg"
      name.textContent = this.nicknames[id]
      const role = document.createElement("span")
      role.className = "block text-sm text-slate-400"
      role.textContent = roles[id] ? roleName(roles[id]) : ""
      text.append(name, role)
      li.append(avatar(this.nicknames[id], "size-10"), icon, text)
      return li
    }))

    this.phaseGameOverTarget.classList.remove("hidden")
    if (changed) {
      this.sounds.chime()
      confetti()
    }
  }

  // ── Rendering ─────────────────────────────────────────────────────────────

  setStory(icon, headline, subline) {
    this.phaseGameOverTarget.classList.add("hidden")
    this.iconTarget.textContent     = icon
    this.headlineTarget.textContent = headline
    this.sublineTarget.textContent  = subline
    this.headlineTarget.classList.remove("hh-appear")
    void this.headlineTarget.offsetWidth // restart the animation
    this.headlineTarget.classList.add("hh-appear")
  }

  renderProgress() {
    if (!this.state || !["night", "vote"].includes(this.state.phase)) return
    const total = (this.state.alive || []).length
    const done  = this.acted.filter(id => this.state.alive.includes(id)).length
    const key   = this.state.phase === "night" ? "haunted_house.ready" : "haunted_house.voted_count"
    this.progressTarget.textContent = t(key, { done, total })
  }

  renderAlive() {
    if (!this.state) return
    const showTicks = ["night", "vote"].includes(this.state.phase)
    this.aliveTarget.replaceChildren(...(this.state.alive || []).map(id => {
      const li = document.createElement("li")
      li.className = "flex items-center justify-between gap-2 rounded-xl bg-slate-800/80 px-3 py-2 font-bold"
      const name = document.createElement("span")
      name.className = "truncate"
      name.textContent = `🎃 ${this.name(id)}`
      const tick = document.createElement("span")
      tick.className = "text-green-400"
      tick.textContent = showTicks && this.acted.includes(id) ? "✓" : ""
      li.append(name, tick)
      return li
    }))
  }

  renderOut() {
    const out = this.state?.out || []
    this.outBoxTarget.classList.toggle("hidden", out.length === 0)
    this.outTarget.replaceChildren(...out.map(o => {
      const li = document.createElement("li")
      li.className = "flex items-center justify-between gap-2 rounded-xl bg-slate-800/50 px-3 py-2 text-slate-400"
      const name = document.createElement("span")
      name.className = "truncate line-through decoration-slate-500"
      name.textContent = this.name(o.id)
      const role = document.createElement("span")
      role.className = "text-sm"
      role.textContent = o.how === "left" ? t("haunted_house.left") : (o.role ? `${ROLE_ICON[o.role]} ${roleName(o.role)}` : "❔")
      li.append(name, role)
      return li
    }))
  }

  // One bar per player who got votes, most first.
  renderTally(tally, out) {
    const rows = Object.entries(tally).sort((a, b) => b[1] - a[1])
    if (rows.length === 0) return
    const max = rows[0][1]
    this.tallyTarget.replaceChildren(...rows.map(([id, count]) => {
      const row = document.createElement("div")
      row.className = "flex items-center gap-3 text-left"
      const name = document.createElement("span")
      name.className = `w-36 truncate font-black text-xl ${id === out ? "text-orange-300" : ""}`
      name.textContent = this.name(id)
      const bar = document.createElement("div")
      bar.className = "h-6 flex-1 rounded-full bg-slate-800"
      const fill = document.createElement("div")
      fill.className = `h-6 rounded-full ${id === out ? "bg-orange-500" : "bg-slate-500"}`
      fill.style.width = `${(count / max) * 100}%`
      bar.append(fill)
      const label = document.createElement("span")
      label.className = "w-20 text-right text-slate-300 font-bold"
      label.textContent = t("haunted_house.votes", { count })
      row.append(name, bar, label)
      return row
    }))
    this.tallyTarget.classList.remove("hidden")
  }

  name(id) {
    return this.nicknames[id] || "?"
  }
}
