import { Controller } from "@hotwired/stimulus"
import consumer from "channels/consumer"
import { t } from "controllers/shared/i18n"
import { avatar } from "controllers/shared/avatar"
import { confetti } from "controllers/shared/celebration"
import { startCountdown, stopCountdown } from "controllers/haunted_house/common"
import { TEAMS, TEAM_ICON, TEAM_LOOK, teamName, injectStyles, replay, TugSounds } from "controllers/tug_of_war/common"

const ROPE_TRAVEL = 0.18 // of the field's width: from the middle to a team's line (the view's 32 % / 68 %)
const STREAK_SHOWN = 3   // pulls in a row before the TV shows the streak

// The TV. Both teams hold the rope; on the teams screen the host taps a player to move them to the
// other team. Every correct answer on a phone ("pull") slides the rope, jolts the player and floats
// a "+1" over them. The server sends the state on every phase change ("state"), "teams" when they
// change, and "pull" / "frozen" as they happen.
export default class extends Controller {
  static values  = { roomCode: String }
  static targets = [
    "soundButton", "roundLabel", "wins", "countdown", "stage", "rope", "redTeam", "blueTeam",
    "redName", "blueName", "redPulls", "bluePulls", "redStreak", "blueStreak",
    "teamsPanel", "startButton", "teamsWarning", "countdownOverlay", "countdownKicker", "countdownNumber",
    "roundOver", "roundOverTitle", "roundOverScore", "skipButton", "toasts",
    "phaseGameOver", "gameOverTitle", "gameOverHint", "mvp", "finalRed", "finalBlue"
  ]

  connect() {
    injectStyles()
    this.sounds     = new TugSounds()
    this.state      = null
    this.nicknames  = {}
    this.soundLabel = this.soundButtonTarget.textContent.trim().replace(/^\S+\s*/, "")
    this.unlockSound = () => this.sounds.unlock()
    document.addEventListener("pointerdown", this.unlockSound)
    this.redNameTarget.textContent  = teamName("red")
    this.blueNameTarget.textContent = teamName("blue")

    this.channel = consumer.subscriptions.create(
      { channel: "Games::TugOfWarChannel", room_code: this.roomCodeValue, player_id: "" },
      {
        connected: () => this.channel.perform("start_game_loop", {}),
        received:  (data) => this.handleMessage(data)
      }
    )
  }

  disconnect() {
    document.removeEventListener("pointerdown", this.unlockSound)
    stopCountdown(this.countdownTarget)
    clearInterval(this.countdownTimer)
    this.sounds.close()
    this.channel?.unsubscribe()
  }

  handleMessage(data) {
    switch (data.action) {
      case "state":          this.onState(data); break
      case "teams":          this.onTeams(data); break
      case "pull":           this.onPull(data); break
      case "frozen":         this.onFrozen(data); break
      case "player_left":    this.channel.perform("sync", {}); break
      case "game_restarted": window.location.reload(); break
      case "game_changed":   window.location.href = `/rooms/${this.roomCodeValue}`; break
      case "game_error":     this.toast(`💥 ${t("tug_of_war.error")}`, "bg-red-700"); break
    }
  }

  // ── Actions ───────────────────────────────────────────────────────────────

  // On the teams screen a tap on a player moves them to the other team.
  movePlayer(event) {
    if (this.state?.phase !== "teams") return
    this.channel.perform("move_player", { player_id: event.currentTarget.dataset.playerId })
  }

  shuffle() {
    this.channel.perform("shuffle_teams", {})
  }

  startPulling() {
    this.startButtonTarget.disabled = true
    this.channel.perform("start_pulling", {})
  }

  skip() {
    this.skipButtonTarget.disabled = true
    this.channel.perform("skip", {})
  }

  restart(event) {
    event.currentTarget.disabled = true
    this.channel.perform("restart_game", {})
  }

  toggleSound() {
    const on = this.sounds.toggle()
    this.soundButtonTarget.textContent = `${on ? "🔊" : "🔇"} ${this.soundLabel}`
    this.soundButtonTarget.classList.toggle("opacity-50", !on)
  }

  // ── State ─────────────────────────────────────────────────────────────────

  onState({ state, nicknames }) {
    const previous = this.state
    const changed  = previous?.phase !== state.phase || previous?.round !== state.round
    this.state     = state
    this.nicknames = nicknames || {}

    this.roundLabelTarget.textContent = state.round && state.total_rounds > 1
      ? t("tug_of_war.round", { round: state.round, total: state.total_rounds }) : ""
    this.renderWins()
    this.renderTeams()
    this.moveRope(state.position)
    this.renderPulls()
    this.renderStreak(state.streak)

    this.teamsPanelTarget.classList.toggle("hidden", state.phase !== "teams")
    this.countdownOverlayTarget.classList.toggle("hidden", state.phase !== "countdown")
    this.roundOverTarget.classList.add("hidden")
    this.phaseGameOverTarget.classList.add("hidden")
    if (state.phase === "pulling") startCountdown(this.countdownTarget, state.seconds_left)
    else stopCountdown(this.countdownTarget)

    switch (state.phase) {
      case "teams":      this.showTeams(); break
      case "countdown":  this.showCountdown(changed); break
      case "pulling":    if (changed) this.showGo(); break
      case "round_over": this.showRoundOver(changed); break
      case "game_over":  this.showGameOver(changed); break
    }
  }

  onTeams({ teams, team_sizes, nicknames }) {
    if (!this.state) return
    this.state.teams      = teams
    this.state.team_sizes = team_sizes
    this.nicknames        = nicknames || this.nicknames
    this.renderTeams()
    this.renderPulls()
    if (this.state.phase === "teams") this.showTeams()
  }

  onPull(data) {
    if (!this.state) return
    this.state.position   = data.position
    this.state.team_pulls = data.team_pulls
    this.state.pulls      = { ...(this.state.pulls || {}), [data.player_id]: data.pulls }
    this.moveRope(data.position)
    this.renderPulls()
    this.renderStreak(data.streak)
    this.sounds.pull(data.team)

    const player = this.playerEl(data.player_id)
    if (!player) return
    replay(player.querySelector("[data-body]"), "tw-tug")
    player.querySelector("[data-plus]")?.remove() // one at a time, however fast they pull
    const plus = document.createElement("span")
    plus.dataset.plus = ""
    plus.className = `tw-float pointer-events-none absolute left-1/2 -top-8 whitespace-nowrap rounded-full px-3 py-1 text-lg font-black shadow-lg ${TEAM_LOOK[data.team].solid}`
    plus.textContent = `+1 💪 ${this.name(data.player_id)}`
    player.append(plus)
    setTimeout(() => plus.remove(), 1500)
  }

  // ❄️ over the player for as long as their phone is frozen.
  onFrozen({ player_id, seconds }) {
    const player = this.playerEl(player_id)
    if (!player) return
    player.querySelector("[data-frozen]")?.remove()
    const ice = document.createElement("span")
    ice.dataset.frozen = ""
    ice.className = "tw-pop pointer-events-none absolute -right-2 -top-2 text-2xl"
    ice.textContent = "❄️"
    player.append(ice)
    setTimeout(() => ice.remove(), seconds * 1000)
  }

  // ── Phases ────────────────────────────────────────────────────────────────

  showTeams() {
    const sizes = this.state.team_sizes || {}
    const ready = TEAMS.every(team => sizes[team] > 0)
    this.startButtonTarget.disabled = !ready
    this.teamsWarningTarget.classList.toggle("hidden", ready)
  }

  // 3, 2, 1 counted on this screen from what the server said.
  showCountdown(changed) {
    this.countdownKickerTarget.textContent = this.state.total_rounds > 1
      ? t("tug_of_war.round", { round: this.state.round, total: this.state.total_rounds }) : t("tug_of_war.get_ready")
    if (!changed) return

    clearInterval(this.countdownTimer)
    const ends = Date.now() + (this.state.seconds_left || 3) * 1000
    let shown = null
    const tick = () => {
      const left = Math.max(1, Math.ceil((ends - Date.now()) / 1000))
      if (left === shown) return
      shown = left
      this.countdownNumberTarget.textContent = left
      replay(this.countdownNumberTarget, "tw-pop")
      this.sounds.beep()
    }
    tick()
    this.countdownTimer = setInterval(tick, 100)
  }

  showGo() {
    clearInterval(this.countdownTimer)
    this.countdownOverlayTarget.classList.remove("hidden")
    this.countdownKickerTarget.textContent = ""
    this.countdownNumberTarget.textContent = t("tug_of_war.go")
    replay(this.countdownNumberTarget, "tw-pop")
    this.sounds.beep(true)
    setTimeout(() => { if (this.state?.phase === "pulling") this.countdownOverlayTarget.classList.add("hidden") }, 900)
  }

  showRoundOver(changed) {
    const winner = this.state.winner
    this.roundOverTitleTarget.textContent = TEAMS.includes(winner)
      ? `${TEAM_ICON[winner]} ${t("tug_of_war.round_winner", { team: teamName(winner) })}`
      : t("tug_of_war.round_draw")
    this.roundOverTitleTarget.className = `font-black text-6xl text-balance tw-pop ${TEAM_LOOK[winner]?.text || "text-white"}`
    this.roundOverScoreTarget.textContent = this.state.total_rounds > 1 ? this.winsText() : ""
    this.skipButtonTarget.disabled = false
    this.roundOverTarget.classList.remove("hidden")
    if (changed) { this.sounds.drumroll(0.8); if (TEAMS.includes(winner)) confetti(40) }
  }

  showGameOver(changed) {
    const champion = this.state.champion
    this.gameOverTitleTarget.textContent = TEAMS.includes(champion)
      ? `${TEAM_ICON[champion]} ${t("tug_of_war.game_winner", { team: teamName(champion) })}`
      : t("tug_of_war.game_draw")
    this.gameOverTitleTarget.className = `text-5xl font-black tracking-wide ${TEAM_LOOK[champion]?.text || "text-white"}`
    this.gameOverHintTarget.textContent = this.state.total_rounds > 1 ? this.winsText() : ""
    const mvp = this.state.mvp || []
    this.mvpTarget.textContent = mvp.length
      ? t("tug_of_war.mvp", { names: mvp.map(id => this.name(id)).join(", "), count: this.state.pulls?.[mvp[0]] || 0 }) : ""

    this.finalRedTarget.replaceChildren(...this.finalRows("red"))
    this.finalBlueTarget.replaceChildren(...this.finalRows("blue"))
    this.phaseGameOverTarget.classList.remove("hidden")
    if (changed) { this.sounds.chime(); confetti() }
  }

  // One team's players, most pulls first.
  finalRows(team) {
    const pulls   = this.state.pulls || {}
    const members = this.members(team).sort((a, b) => (pulls[b] || 0) - (pulls[a] || 0))
    const title   = document.createElement("p")
    title.className = `font-black text-xl ${TEAM_LOOK[team].text}`
    title.textContent = `${TEAM_ICON[team]} ${teamName(team)}`
    return [ title, ...members.map(id => {
      const row = document.createElement("div")
      row.className = `flex items-center gap-3 rounded-xl px-4 py-2 font-bold bg-slate-800`
      const name = document.createElement("span")
      name.className = "flex-1 truncate"
      name.textContent = this.name(id)
      const count = document.createElement("span")
      count.className = "tabular-nums text-slate-300"
      count.textContent = t("tug_of_war.pulls", { count: pulls[id] || 0 })
      const face = avatar(this.name(id), "size-8")
      face.classList.add("ring-2", TEAM_LOOK[team].ring)
      row.append(face, name, count)
      return row
    }) ]
  }

  // ── Rendering ─────────────────────────────────────────────────────────────

  // Both teams along the rope, the nearest to the flag first, alternately above and below it.
  renderTeams() {
    const editable = this.state?.phase === "teams"
    TEAMS.forEach(team => {
      const members = this.members(team)
      const size    = members.length > 8 ? "size-12" : members.length > 4 ? "size-16" : "size-20"
      const players = members.map((id, i) => {
        const el = document.createElement("button")
        el.type = "button"
        el.dataset.playerId = id
        el.dataset.action = "tug-of-war-host#movePlayer"
        el.disabled = !editable
        el.className = `relative flex flex-col items-center min-w-0 shrink ${editable ? "cursor-pointer hover:scale-110 transition-transform" : "cursor-default"}`
        el.style.transform = `translateY(${i % 2 ? 34 : -34}px)`
        el.title = editable ? t("tug_of_war.move_to", { team: teamName(team === "red" ? "blue" : "red") }) : ""

        const body = document.createElement("span")
        body.dataset.body = ""
        body.style.setProperty("--dir", team === "red" ? -1 : 1)
        body.className = "flex flex-col items-center"
        const face = avatar(this.name(id), size)
        face.classList.add("ring-4", TEAM_LOOK[team].ring, "bg-slate-900")
        const name = document.createElement("span")
        name.className = "mt-1 max-w-28 truncate rounded-full bg-slate-950/80 px-2 text-sm font-bold"
        name.textContent = this.name(id)
        body.append(face, name)
        el.append(body)
        return el
      })
      this[`${team}TeamTarget`].replaceChildren(...players)
    })
  }

  moveRope(position) {
    const percent = (Math.max(-100, Math.min(100, Number(position) || 0)) / 100) * ROPE_TRAVEL * 100
    this.ropeTarget.style.transform = `translateX(${percent}%)`
  }

  renderPulls() {
    const pulls = this.state?.team_pulls || {}
    TEAMS.forEach(team => {
      this[`${team}PullsTarget`].textContent = this.state?.phase === "teams"
        ? t("tug_of_war.players", { count: this.members(team).length })
        : t("tug_of_war.pulls", { count: pulls[team] || 0 })
    })
  }

  renderStreak(streak) {
    TEAMS.forEach(team => {
      const el    = this[`${team}StreakTarget`]
      const shown = streak?.team === team && streak.count >= STREAK_SHOWN && this.state?.phase === "pulling"
      el.classList.toggle("hidden", !shown)
      if (!shown) return
      const text = t("tug_of_war.streak", { count: streak.count })
      if (el.textContent !== text) { el.textContent = text; replay(el, "tw-pop") }
    })
  }

  renderWins() {
    const shown = this.state.total_rounds > 1 && this.state.round > 0
    this.winsTarget.classList.toggle("hidden", !shown)
    if (shown) this.winsTarget.textContent = this.winsText()
  }

  winsText() {
    const wins = this.state.wins || {}
    return `${TEAM_ICON.red} ${wins.red || 0} – ${wins.blue || 0} ${TEAM_ICON.blue}`
  }

  members(team) {
    return Object.entries(this.state?.teams || {}).filter(([, side]) => side === team).map(([ id ]) => id)
  }

  playerEl(id) {
    return this.ropeTarget.querySelector(`[data-player-id="${CSS.escape(id)}"]`)
  }

  toast(text, classes) {
    const el = document.createElement("p")
    el.className = `tw-toast rounded-full px-5 py-2 font-bold text-lg shadow-lg ${classes}`
    el.textContent = text
    this.toastsTarget.append(el)
    setTimeout(() => el.remove(), 3000)
  }

  name(id) {
    return this.nicknames[id] || "?"
  }
}
