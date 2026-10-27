import { Controller } from "@hotwired/stimulus"
import consumer from "channels/consumer"
import { t } from "controllers/shared/i18n"
import { celebrateWin } from "controllers/shared/celebration"
import { startCountdown, stopCountdown } from "controllers/haunted_house/common"
import { TEAMS, TEAM_ICON, TEAM_LOOK, teamName, ropePercent, injectStyles, replay } from "controllers/tug_of_war/common"

const MAX_DIGITS = 4

// A phone. Shows the player's team, then during each round their own math problem: typed on the
// keypad or picked from four answers (the room's setting). Each answer goes to the server
// ("answer_result" comes back with the next problem); a wrong one freezes the phone for 2 seconds.
// The phone's problems come on its own stream ("problem") or with "state" on connecting.
export default class extends Controller {
  static values  = { roomCode: String, playerId: String }
  static targets = [
    "teamChip", "countdown", "flag", "myPulls",
    "phaseMessage", "messageIcon", "messageTitle", "messageHint",
    "phaseCountdown", "countdownNumber",
    "phasePulling", "problem", "typed", "feedback", "frozen", "frozenAnswer", "frozenSeconds", "keypad", "choices",
    "phaseGameOver", "gameOverIcon", "gameOverTitle", "gameOverHint", "gameOverMvp"
  ]

  connect() {
    injectStyles()
    this.state     = null
    this.nicknames = {}
    this.team      = null
    this.problem   = null
    this.typedText = ""
    this.answerId  = 0
    this.pending   = null // the answer waiting for its result
    this.onKey = (event) => this.key(event)
    document.addEventListener("keydown", this.onKey)
    this.keepAwake()

    this.channel = consumer.subscriptions.create(
      { channel: "Games::TugOfWarChannel", room_code: this.roomCodeValue, player_id: this.playerIdValue },
      {
        rejected: () => window.location.reload(),
        received: (data) => this.handleMessage(data)
      }
    )
  }

  disconnect() {
    document.removeEventListener("keydown", this.onKey)
    document.removeEventListener("visibilitychange", this.onVisible)
    stopCountdown(this.countdownTarget)
    clearInterval(this.countdownTimer)
    clearInterval(this.frozenTimer)
    clearTimeout(this.feedbackTimer)
    this.wakeLock?.release().catch(() => {})
    this.channel?.unsubscribe()
  }

  handleMessage(data) {
    switch (data.action) {
      case "state":          this.onState(data); break
      case "problem":        this.setProblem(data.problem); break
      case "answer_result":  this.onAnswerResult(data); break
      case "teams":          this.onTeams(data); break
      case "pull":           this.onPull(data); break
      case "player_left":    this.channel.perform("sync", {}); break
      case "game_restarted": window.location.reload(); break
      case "game_changed":   window.location.href = `/rooms/${this.roomCodeValue}`; break
    }
  }

  // ── Actions ───────────────────────────────────────────────────────────────

  press(event) {
    if (!this.canAnswer() || this.typedText.length >= MAX_DIGITS) return
    this.typedText = this.typedText === "0" ? event.currentTarget.dataset.digit : this.typedText + event.currentTarget.dataset.digit
    this.renderTyped()
  }

  erase() {
    this.typedText = this.typedText.slice(0, -1)
    this.renderTyped()
  }

  submit() {
    if (this.typedText === "") return
    this.send(this.typedText)
  }

  choose(event) {
    this.send(event.currentTarget.dataset.value)
  }

  // A computer keyboard works too: digits, Backspace, Enter.
  key(event) {
    if (this.state?.phase !== "pulling" || this.state.answer_mode !== "type") return
    if (/^\d$/.test(event.key)) this.press({ currentTarget: { dataset: { digit: event.key } } })
    else if (event.key === "Backspace") this.erase()
    else if (event.key === "Enter") this.submit()
  }

  send(value) {
    if (!this.canAnswer()) return
    this.pending = { id: ++this.answerId }
    this.renderInputs()
    this.channel.perform("answer", { problem_id: this.problem.id, value: String(value), id: this.answerId })
  }

  canAnswer() {
    return this.state?.phase === "pulling" && this.problem && !this.frozen && !this.pending
  }

  // ── Server messages ───────────────────────────────────────────────────────

  onState({ state, nicknames }) {
    const previous = this.state
    const newRound = previous?.round !== state.round
    const changed  = previous?.phase !== state.phase || newRound
    this.state     = state
    this.nicknames = nicknames || this.nicknames

    this.setTeam(state.team || state.teams?.[this.playerIdValue])
    if (newRound) { this.pending = null; this.unfreeze() }
    if ("problem" in state) this.setProblem(state.problem)
    if (state.frozen_seconds > 0) this.freeze(state.frozen_seconds)
    this.moveFlag(state.position)
    this.renderMyPulls()
    if (state.phase === "pulling") startCountdown(this.countdownTarget, state.seconds_left)
    else stopCountdown(this.countdownTarget)

    switch (state.phase) {
      case "teams":      this.showMessage(TEAM_ICON[this.team] || "🪢", t("tug_of_war.team_label", { team: teamName(this.team) }), t("tug_of_war.teams_wait")); break
      case "countdown":  this.showCountdown(changed); break
      case "pulling":    this.showPulling(); break
      case "round_over": this.showRoundOver(); break
      case "game_over":  if (previous?.phase !== "game_over") this.showGameOver(); break
      default:           this.showMessage("🪢", t("tug_of_war.get_ready"), "")
    }
  }

  onTeams({ teams, nicknames }) {
    if (!this.state) return
    this.state.teams = teams
    this.nicknames   = nicknames || this.nicknames
    const before = this.team
    this.setTeam(teams[this.playerIdValue])
    if (this.state.phase === "teams") {
      this.showMessage(TEAM_ICON[this.team] || "🪢", t("tug_of_war.team_label", { team: teamName(this.team) }), t("tug_of_war.teams_wait"))
      if (before && before !== this.team) replay(this.messageTitleTarget, "tw-pop")
    }
  }

  onPull(data) {
    if (!this.state) return
    this.state.position = data.position
    this.moveFlag(data.position)
  }

  onAnswerResult(data) {
    if (data.id !== this.pending?.id) return
    this.pending = null

    switch (data.result) {
      case "correct":
        this.state.pulls = { ...(this.state.pulls || {}), [this.playerIdValue]: data.pulls }
        this.state.position = data.position
        this.moveFlag(data.position)
        this.renderMyPulls()
        this.feedback(t("tug_of_war.correct"), "text-emerald-400")
        navigator.vibrate?.(30)
        this.setProblem(data.problem)
        break
      case "wrong":
        navigator.vibrate?.([ 60, 40, 60 ])
        this.frozenAnswerTarget.textContent = t("tug_of_war.wrong", { text: this.problem?.text || "", answer: data.answer })
        this.freeze(data.seconds)
        this.setProblem(data.problem)
        break
      case "frozen":
        this.freeze(data.seconds)
        break
      case "stale":
        this.setProblem(data.problem)
        break
      default: // the round is over
        this.typedText = ""
        this.renderTyped()
        this.renderInputs()
    }
  }

  // ── Problem and answers ───────────────────────────────────────────────────

  setProblem(problem) {
    this.problem   = problem || null
    this.typedText = ""
    this.problemTarget.textContent = problem ? `${problem.text} = ?` : ""
    if (problem) replay(this.problemTarget, "tw-pop")
    this.renderTyped()
    this.renderInputs()
  }

  renderTyped() {
    this.typedTarget.textContent = this.typedText || "?"
    this.typedTarget.classList.toggle("text-slate-600", this.typedText === "")
  }

  // The keypad or the four answers, by the room's setting; dimmed while waiting or frozen.
  renderInputs() {
    const choice = this.state?.answer_mode === "choice"
    const busy   = !!this.pending || this.frozen
    this.keypadTarget.classList.toggle("hidden", choice)
    this.typedTarget.classList.toggle("hidden", choice)
    this.choicesTarget.classList.toggle("hidden", !choice)
    this.keypadTarget.classList.toggle("opacity-50", busy)
    this.choicesTarget.classList.toggle("opacity-50", busy)
    if (!choice) return

    const buttons = (this.problem?.choices || []).map(value => {
      const button = document.createElement("button")
      button.type = "button"
      button.dataset.value = value
      button.dataset.action = "tug-of-war-player#choose"
      button.disabled = busy
      button.className = "h-24 rounded-2xl bg-slate-800 border-2 border-slate-600 text-4xl font-black tabular-nums active:scale-95 active:bg-slate-700 cursor-pointer"
      button.textContent = value
      return button
    })
    this.choicesTarget.replaceChildren(...buttons)
  }

  freeze(seconds) {
    clearInterval(this.frozenTimer)
    this.frozen = true
    const ends = Date.now() + seconds * 1000
    this.frozenTarget.classList.remove("hidden")
    const tick = () => {
      const left = (ends - Date.now()) / 1000
      if (left <= 0) return this.unfreeze()
      this.frozenSecondsTarget.textContent = Math.ceil(left)
    }
    tick()
    this.frozenTimer = setInterval(tick, 100)
    this.renderInputs()
  }

  unfreeze() {
    clearInterval(this.frozenTimer)
    this.frozen = false
    this.frozenTarget.classList.add("hidden")
    this.frozenAnswerTarget.textContent = ""
    this.renderInputs()
  }

  feedback(text, color) {
    clearTimeout(this.feedbackTimer)
    this.feedbackTarget.textContent = text
    this.feedbackTarget.className = `absolute inset-x-4 bottom-3 text-center font-black text-2xl tw-pop ${color}`
    this.feedbackTimer = setTimeout(() => this.feedbackTarget.classList.add("hidden"), 700)
  }

  // ── Phases ────────────────────────────────────────────────────────────────

  showPhase(name) {
    [ "phaseMessage", "phaseCountdown", "phasePulling" ].forEach(p => {
      this[`${p}Target`].classList.toggle("hidden", p !== name)
    })
    this.phaseGameOverTarget.classList.toggle("hidden", name !== "phaseGameOver")
  }

  showMessage(icon, title, hint) {
    this.showPhase("phaseMessage")
    this.messageIconTarget.textContent  = icon
    this.messageTitleTarget.textContent = title
    this.messageHintTarget.textContent  = hint
  }

  showCountdown(changed) {
    this.showPhase("phaseCountdown")
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
    }
    tick()
    this.countdownTimer = setInterval(tick, 100)
  }

  showPulling() {
    clearInterval(this.countdownTimer)
    this.showPhase("phasePulling")
    this.renderInputs()
    if (!this.problem) this.channel.perform("sync", {}) // its problem got lost on the way
  }

  showRoundOver() {
    const winner = this.state.winner
    const wins   = this.state.wins || {}
    const score  = this.state.total_rounds > 1 ? `${TEAM_ICON.red} ${wins.red || 0} – ${wins.blue || 0} ${TEAM_ICON.blue}` : ""
    if (!TEAMS.includes(winner)) return this.showMessage("🤝", t("tug_of_war.round_draw"), score)
    const ours = winner === this.team
    this.showMessage(ours ? "🎉" : "😤", ours ? t("tug_of_war.you_won_round") : t("tug_of_war.you_lost_round"), score)
  }

  showGameOver() {
    clearInterval(this.frozenTimer)
    const champion = this.state.champion
    const won      = (this.state.winners || []).includes(this.playerIdValue)
    this.gameOverIconTarget.textContent  = TEAMS.includes(champion) ? (won ? "🏆" : "💪") : "🤝"
    this.gameOverTitleTarget.textContent = TEAMS.includes(champion) ? (won ? t("tug_of_war.you_win") : t("tug_of_war.you_lose")) : t("tug_of_war.game_draw")
    this.gameOverHintTarget.textContent  = t("tug_of_war.your_pulls", { count: this.state.pulls?.[this.playerIdValue] || 0 })
    const mvp = this.state.mvp || []
    this.gameOverMvpTarget.textContent = mvp.includes(this.playerIdValue) ? t("tug_of_war.you_mvp") : ""
    this.showPhase("phaseGameOver")
    if (won) celebrateWin(this.gameOverTitleTarget)
  }

  // ── Rendering ─────────────────────────────────────────────────────────────

  setTeam(team) {
    if (!TEAMS.includes(team)) return
    this.team = team
    const look = TEAM_LOOK[team]
    this.teamChipTarget.textContent = `${TEAM_ICON[team]} ${teamName(team)}`
    this.teamChipTarget.className = `rounded-full px-3 py-1 text-sm font-black whitespace-nowrap text-white ${look.solid}`
    TEAMS.forEach(other => this.element.classList.toggle(TEAM_LOOK[other].page, other === team))
    this.element.classList.toggle("bg-slate-950", false)
  }

  moveFlag(position) {
    this.flagTarget.style.left = `${ropePercent(position)}%`
  }

  renderMyPulls() {
    const phase = this.state?.phase
    this.myPullsTarget.textContent = phase && phase !== "teams"
      ? t("tug_of_war.your_pulls", { count: this.state.pulls?.[this.playerIdValue] || 0 }) : ""
  }

  // Keep the screen on while playing.
  async keepAwake() {
    if (!("wakeLock" in navigator)) return
    const request = async () => { try { this.wakeLock = await navigator.wakeLock.request("screen") } catch {} }
    this.onVisible = () => { if (document.visibilityState === "visible") request() }
    document.addEventListener("visibilitychange", this.onVisible)
    request()
  }
}
