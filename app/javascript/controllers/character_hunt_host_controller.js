import { Controller } from "@hotwired/stimulus"
import consumer from "channels/consumer"
import { t } from "controllers/shared/i18n"
import { avatar } from "controllers/shared/avatar"
import { confetti } from "controllers/shared/celebration"
import { startCountdown, stopCountdown, Sounds } from "controllers/haunted_house/common"
import { drawScene, drawMark, drawPortrait } from "controllers/character_hunt/scene"
import { Viewport } from "controllers/character_hunt/viewport"
import { injectStyles, placeLabel, replay } from "controllers/character_hunt/common"

// The TV. Shows who to find, then the whole scene while the phones search, who found them, and
// at the reveal glides in on where the target stood. The server sends the state on every phase
// change ("state"), and "found" / "frozen" as they happen.
export default class extends Controller {
  static values  = { roomCode: String, catalog: Object }
  static targets = [
    "soundButton", "roundLabel", "scene", "intro", "introKicker", "introTitle", "introPortrait", "introCountdown",
    "banner", "toasts", "sidePortrait", "countdown", "finders", "skipButton",
    "phaseGameOver", "gameOverTitle", "gameOverHint", "finalScores"
  ]

  connect() {
    injectStyles()
    this.sounds     = new Sounds()
    this.state      = null
    this.nicknames  = {}
    this.marks      = []
    this.soundLabel = this.soundButtonTarget.textContent.trim().replace(/^\S+\s*/, "")
    this.unlockSound = () => this.sounds.unlock()
    document.addEventListener("pointerdown", this.unlockSound)

    this.channel = consumer.subscriptions.create(
      { channel: "Games::CharacterHuntChannel", room_code: this.roomCodeValue, player_id: "" },
      {
        connected: () => this.channel.perform("start_game_loop", {}),
        received:  (data) => this.handleMessage(data)
      }
    )
  }

  disconnect() {
    document.removeEventListener("pointerdown", this.unlockSound)
    stopCountdown(this.countdownTarget)
    stopCountdown(this.introCountdownTarget)
    this.viewport?.destroy()
    this.sounds.close()
    this.channel?.unsubscribe()
  }

  handleMessage(data) {
    switch (data.action) {
      case "state":          this.onState(data); break
      case "found":          this.onFound(data); break
      case "frozen":         this.toast(`❄️ ${t("character_hunt.frozen_tv", { name: this.name(data.player_id) })}`, "bg-sky-900"); break
      case "player_left":    this.channel.perform("sync", {}); break
      case "game_restarted": window.location.reload(); break
      case "game_changed":   window.location.href = `/rooms/${this.roomCodeValue}`; break
      case "game_error":     this.showIntro("💥", t("character_hunt.error")); break
    }
  }

  // ── Actions ───────────────────────────────────────────────────────────────

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

    this.roundLabelTarget.textContent = state.round ? t("character_hunt.round", { round: state.round, total: state.total_rounds }) : ""
    if (state.scene && (previous?.round !== state.round || !this.viewport)) this.setScene(state.scene)
    this.bannerTarget.classList.add("hidden")
    this.skipButtonTarget.classList.add("hidden")
    stopCountdown(this.introCountdownTarget)

    switch (state.phase) {
      case "intro":     this.showWhoToFind(changed); break
      case "search":    this.showSearch(changed); break
      case "reveal":    this.showReveal(changed); break
      case "game_over": this.showGameOver(changed); break
      default:          this.showIntro("", t("character_hunt.get_ready"))
    }

    if (state.target) drawPortrait(this.sidePortraitTarget, state.target, this.catalogValue)
    if (state.phase === "game_over") stopCountdown(this.countdownTarget)
    else startCountdown(this.countdownTarget, state.phase === "intro" ? null : state.seconds_left)
    this.renderFinders()
  }

  setScene(scene) {
    this.viewport?.destroy()
    this.scene = scene
    this.marks = []
    this.viewport = new Viewport(this.sceneTarget, {
      ratio: scene.ratio, interactive: false, background: "#020617",
      draw: ctx => {
        drawScene(ctx, scene, this.catalogValue)
        this.marks.forEach(({ index, color }) => drawMark(ctx, scene, index, color))
      }
    })
  }

  showWhoToFind(changed) {
    this.showIntro(t("character_hunt.round", { round: this.state.round, total: this.state.total_rounds }), t("character_hunt.find_this"))
    this.introPortraitTarget.classList.remove("hidden")
    drawPortrait(this.introPortraitTarget, this.state.target, this.catalogValue, "#fef9c3")
    startCountdown(this.introCountdownTarget, this.state.seconds_left)
    if (changed) { replay(this.introPortraitTarget, "ch-pop"); this.sounds.drumroll(1.2) }
  }

  showSearch(changed) {
    this.introTarget.classList.add("hidden")
    this.phaseGameOverTarget.classList.add("hidden")
    if (changed) { this.marks = []; this.viewport?.reset() }
  }

  // The scene glides in on the target, ringed in yellow.
  showReveal(changed) {
    this.introTarget.classList.add("hidden")
    const index = this.state.target_index
    const c     = this.scene?.characters[index]
    this.bannerTarget.textContent = (this.state.finders || []).length ? t("character_hunt.reveal_title") : t("character_hunt.nobody_found")
    this.bannerTarget.classList.remove("hidden")
    if (changed) replay(this.bannerTarget, "ch-pop")
    this.skipButtonTarget.disabled = false
    this.skipButtonTarget.classList.remove("hidden")
    if (!c) return

    this.marks = [ { index, color: "#facc15" } ]
    if (changed) this.viewport.focus(c.x, c.y - c.h * 0.55, 3.5)
    else this.viewport.render()
  }

  showGameOver(changed) {
    const winners = this.state.winners || []
    this.gameOverTitleTarget.textContent = t("character_hunt.game_over")
    this.gameOverHintTarget.textContent  = winners.length
      ? t("character_hunt.winners", { names: winners.map(id => this.name(id)).join(", ") }) : ""

    const scores = Object.entries(this.state.scores || {}).sort((a, b) => b[1] - a[1])
    this.finalScoresTarget.replaceChildren(...scores.map(([ id, points ]) => {
      const row = document.createElement("div")
      row.className = `flex items-center gap-3 rounded-xl px-4 py-2 font-bold ${winners.includes(id) ? "bg-yellow-400/20 text-yellow-200" : "bg-slate-800"}`
      const name = document.createElement("span")
      name.className = "flex-1 truncate"
      name.textContent = this.name(id)
      const pts = document.createElement("span")
      pts.className = "tabular-nums"
      pts.textContent = points
      row.append(avatar(this.name(id), "size-8"), name, pts)
      return row
    }))
    this.phaseGameOverTarget.classList.remove("hidden")
    if (changed) { this.sounds.chime(); confetti() }
  }

  onFound(data) {
    if (!this.state) return
    this.state.finders = [ ...(this.state.finders || []), { id: data.player_id, time: data.time, points: data.points } ]
    this.state.scores  = data.scores || this.state.scores
    this.renderFinders()
    this.toast(`🎉 ${t("character_hunt.found_by", { name: this.name(data.player_id) })} ${placeLabel(data.place)}`, "bg-yellow-500 text-slate-950")
    this.sounds.chime()
  }

  // ── Rendering ─────────────────────────────────────────────────────────────

  showIntro(kicker, title) {
    this.introTarget.classList.remove("hidden")
    this.introPortraitTarget.classList.add("hidden")
    this.introKickerTarget.textContent = kicker || ""
    this.introTitleTarget.textContent  = title || ""
  }

  // Three places, filled in as players find the target.
  renderFinders() {
    const finders = this.state?.finders || []
    const slots   = [ 1, 2, 3 ].map(place => {
      const finder = finders[place - 1]
      const row    = document.createElement("li")
      const look = finder ? "bg-yellow-400/15 border border-yellow-400/50 ch-pop" : "bg-slate-900 border border-slate-800 text-slate-400"
      row.className = `flex items-center justify-between gap-2 rounded-xl px-4 py-3 font-bold ${look}`
      const name = document.createElement("span")
      name.className = "truncate"
      name.textContent = `${placeLabel(place)}  ${finder ? this.name(finder.id) : "…"}`
      row.append(name)
      if (finder) {
        const time = document.createElement("span")
        time.className = "text-yellow-200 tabular-nums text-sm shrink-0"
        time.textContent = t("character_hunt.seconds", { time: finder.time })
        row.append(time)
      }
      return row
    })
    this.findersTarget.replaceChildren(...slots)
  }

  toast(text, classes) {
    const el = document.createElement("p")
    el.className = `ch-toast rounded-full px-5 py-2 font-bold text-lg shadow-lg ${classes}`
    el.textContent = text
    this.toastsTarget.append(el)
    setTimeout(() => el.remove(), 4000)
  }

  name(id) {
    return this.nicknames[id] || "?"
  }
}
