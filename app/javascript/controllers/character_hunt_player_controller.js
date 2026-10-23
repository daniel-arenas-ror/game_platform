import { Controller } from "@hotwired/stimulus"
import consumer from "channels/consumer"
import { t, placeTitle } from "controllers/shared/i18n"
import { celebrateWin } from "controllers/shared/celebration"
import { startCountdown, stopCountdown } from "controllers/haunted_house/common"
import { drawScene, drawMark, drawPortrait, hitTest } from "controllers/character_hunt/scene"
import { Viewport } from "controllers/character_hunt/viewport"
import { injectStyles, placeLabel, replay } from "controllers/character_hunt/common"

const FINDERS = 3 // GameServices::CharacterHunt::POINTS.size

// A phone. Shows who to find, then the scene to zoom around; a tap goes to the server, which says
// whether it was the target ("tap_result"). A wrong person freezes the phone for a few seconds.
export default class extends Controller {
  static values  = { roomCode: String, playerId: String, catalog: Object }
  static targets = [
    "score", "countdown", "scene", "frozen", "frozenSeconds",
    "intro", "introKicker", "introTitle", "introPortrait", "introHint",
    "message", "messageTitle", "messageHint", "toast", "zoomButtons", "portrait", "progress",
    "phaseGameOver", "gameOverTitle", "gameOverHint"
  ]

  connect() {
    injectStyles()
    this.state     = null
    this.nicknames = {}
    this.marks     = []
    this.tapId     = 0
    this.pending   = null // the tap waiting for its answer
    this.keepAwake()

    this.channel = consumer.subscriptions.create(
      { channel: "Games::CharacterHuntChannel", room_code: this.roomCodeValue, player_id: this.playerIdValue },
      {
        rejected: () => window.location.reload(),
        received: (data) => this.handleMessage(data)
      }
    )
  }

  disconnect() {
    document.removeEventListener("visibilitychange", this.onVisible)
    stopCountdown(this.countdownTarget)
    clearInterval(this.frozenTimer)
    clearTimeout(this.toastTimer)
    this.viewport?.destroy()
    this.wakeLock?.release().catch(() => {})
    this.channel?.unsubscribe()
  }

  handleMessage(data) {
    switch (data.action) {
      case "state":          this.onState(data); break
      case "tap_result":     this.onTapResult(data); break
      case "found":          this.onFound(data); break
      case "player_left":    this.channel.perform("sync", {}); break
      case "game_restarted": window.location.reload(); break
      case "game_changed":   window.location.href = `/rooms/${this.roomCodeValue}`; break
    }
  }

  // ── Actions ───────────────────────────────────────────────────────────────

  zoomIn()  { this.viewport?.zoomBy(1.6) }
  zoomOut() { this.viewport?.zoomBy(1 / 1.6) }
  fit()     { this.viewport?.reset() }

  // A tap on someone. Ignored while frozen, after finding them, or while the last tap is unanswered.
  tap(x, y) {
    if (this.state?.phase !== "search" || this.frozen || this.found || this.pending) return

    const index = hitTest(this.scene, x, y)
    if (index === null) return this.flash(t("character_hunt.nobody_there"))

    this.pending = { id: ++this.tapId, index }
    this.marks = [ { index, color: "#e2e8f0" } ]
    this.viewport.render()
    this.channel.perform("tap", { x, y, id: this.tapId })
  }

  // ── State ─────────────────────────────────────────────────────────────────

  onState({ state, nicknames }) {
    const previous = this.state
    const newRound = previous?.round !== state.round
    const changed  = previous?.phase !== state.phase || newRound
    this.state     = state
    this.nicknames = nicknames || {}

    if (state.scene && (newRound || !this.viewport)) this.setScene(state.scene)
    if (newRound) { this.found = null; this.pending = null; this.unfreeze() }
    this.found ||= (state.finders || []).find(f => f.id === this.playerIdValue)

    this.scoreTarget.textContent = t("character_hunt.points", { count: state.scores?.[this.playerIdValue] ?? 0 })
    if (state.target) drawPortrait(this.portraitTarget, state.target, this.catalogValue)
    if (state.phase === "game_over") stopCountdown(this.countdownTarget)
    else startCountdown(this.countdownTarget, state.seconds_left)

    switch (state.phase) {
      case "intro":     this.showWhoToFind(changed); break
      case "search":    this.showSearch(changed); break
      case "reveal":    this.showReveal(changed); break
      case "game_over": if (previous?.phase !== "game_over") this.showGameOver(); break
      default:          this.showIntro(t("character_hunt.get_ready"), this.element.dataset.lookTv)
    }
    this.renderProgress()
  }

  setScene(scene) {
    this.viewport?.destroy()
    this.scene = scene
    this.marks = []
    this.viewport = new Viewport(this.sceneTarget, {
      ratio: scene.ratio, background: "#020617",
      onTap: (x, y) => this.tap(x, y),
      draw: ctx => {
        drawScene(ctx, scene, this.catalogValue)
        this.marks.forEach(({ index, color }) => drawMark(ctx, scene, index, color))
      }
    })
  }

  showWhoToFind(changed) {
    this.hideMessage()
    this.showIntro(t("character_hunt.find_this"), t("character_hunt.search_hint"),
                   t("character_hunt.round", { round: this.state.round, total: this.state.total_rounds }))
    this.introPortraitTarget.classList.remove("hidden")
    drawPortrait(this.introPortraitTarget, this.state.target, this.catalogValue, "#fef9c3")
    if (changed) replay(this.introPortraitTarget, "ch-pop")
  }

  // Starts filling the screen (on a phone held upright the whole scene is a thin strip).
  showSearch(changed) {
    this.introTarget.classList.add("hidden")
    this.zoomButtonsTarget.classList.remove("hidden")
    if (changed) this.viewport.reset(this.viewport.coverZoom)
    if (this.found) this.showFound(this.found)
    else this.hideMessage()
    if (this.state.frozen_seconds > 0) this.freeze(this.state.frozen_seconds)
  }

  // Everyone sees where the target was, and how they did.
  showReveal(changed) {
    this.introTarget.classList.add("hidden")
    this.zoomButtonsTarget.classList.remove("hidden")
    this.unfreeze()
    const index = this.state.target_index
    const c     = this.scene?.characters[index]
    if (c) {
      this.marks = [ { index, color: "#facc15" } ]
      if (changed) this.viewport.focus(c.x, c.y - c.h * 0.55, 3)
      else this.viewport.render()
    }

    const mine = (this.state.finders || []).find(f => f.id === this.playerIdValue)
    if (mine) this.message(`✅ ${t("character_hunt.reveal_title")}`, this.foundLine(mine))
    else this.message(`👀 ${t("character_hunt.reveal_title")}`, t("character_hunt.not_found"))
  }

  showGameOver() {
    stopCountdown(this.countdownTarget)
    this.unfreeze()
    const scores = this.state.scores || {}
    const mine   = scores[this.playerIdValue] ?? 0
    const rank   = 1 + Object.values(scores).filter(s => s > mine).length
    this.gameOverTitleTarget.textContent = placeTitle(rank)
    this.gameOverHintTarget.textContent  = t("character_hunt.points", { count: mine })
    this.phaseGameOverTarget.classList.remove("hidden")
    if ((this.state.winners || []).includes(this.playerIdValue)) celebrateWin(this.gameOverTitleTarget)
  }

  // ── Taps ──────────────────────────────────────────────────────────────────

  onTapResult(data) {
    if (data.id !== this.pending?.id) return
    const { index } = this.pending
    this.pending = null

    switch (data.result) {
      case "found":
        this.found = { id: this.playerIdValue, place: data.place, points: data.points, time: data.time }
        this.marks = [ { index, color: "#22c55e" } ]
        navigator.vibrate?.([ 60, 40, 60 ])
        this.showFound(this.found)
        break
      case "wrong":
        this.marks = [ { index, color: "#ef4444" } ]
        navigator.vibrate?.(250)
        this.freeze(data.seconds)
        break
      case "frozen":
        this.marks = []
        this.freeze(data.seconds)
        break
      case "closed":
        this.marks = []
        if (this.state?.phase === "search" && !this.found) this.message(`⏱️ ${t("character_hunt.too_late")}`, "")
        break
      default:
        this.marks = []
    }
    this.viewport?.render()
  }

  onFound(data) {
    if (!this.state) return
    if (!(this.state.finders || []).some(f => f.id === data.player_id)) {
      this.state.finders = [ ...(this.state.finders || []), { id: data.player_id, time: data.time, points: data.points } ]
    }
    this.state.scores = data.scores || this.state.scores
    this.scoreTarget.textContent = t("character_hunt.points", { count: this.state.scores?.[this.playerIdValue] ?? 0 })
    this.renderProgress()
    if (data.player_id !== this.playerIdValue) {
      this.flash(`${placeLabel(data.place)} ${t("character_hunt.found_by", { name: this.name(data.player_id) })}`)
    }
  }

  // Frozen for `seconds`: the scene can still be moved around, not tapped.
  freeze(seconds) {
    clearInterval(this.frozenTimer)
    const ends = Date.now() + seconds * 1000
    this.frozen = true
    this.frozenTarget.classList.remove("hidden")
    const tick = () => {
      const left = Math.ceil((ends - Date.now()) / 1000)
      if (left <= 0) return this.unfreeze()
      this.frozenSecondsTarget.textContent = left
    }
    tick()
    this.frozenTimer = setInterval(tick, 200)
  }

  unfreeze() {
    clearInterval(this.frozenTimer)
    this.frozen = false
    this.frozenTarget.classList.add("hidden")
    if (this.marks.some(m => m.color === "#ef4444")) { this.marks = []; this.viewport?.render() }
  }

  // ── Rendering ─────────────────────────────────────────────────────────────

  showFound(found) {
    this.message(`🎉 ${t("character_hunt.found_you")}`, this.foundLine(found))
  }

  foundLine(found) {
    const place = found.place || (this.state.finders || []).findIndex(f => f.id === found.id) + 1
    return `${placeLabel(place)} · ${t("character_hunt.plus_points", { count: found.points })} · ${t("character_hunt.seconds", { time: found.time })}`
  }

  renderProgress() {
    const s = this.state
    if (!s || ![ "search", "reveal" ].includes(s.phase)) {
      this.progressTarget.textContent = s?.target ? t("character_hunt.find_this") : ""
      return
    }
    const needed = Math.min(FINDERS, Object.keys(this.nicknames).length || FINDERS)
    this.progressTarget.textContent = t("character_hunt.found_count", { found: (s.finders || []).length, total: needed })
  }

  showIntro(title, hint, kicker = "") {
    this.zoomButtonsTarget.classList.add("hidden")
    this.introTarget.classList.remove("hidden")
    this.introPortraitTarget.classList.add("hidden")
    this.introKickerTarget.textContent = kicker
    this.introTitleTarget.textContent  = title || ""
    this.introHintTarget.textContent   = hint || ""
  }

  message(title, hint) {
    this.messageTitleTarget.textContent = title
    this.messageHintTarget.textContent  = hint || ""
    this.messageTarget.classList.remove("hidden")
    replay(this.messageTarget, "ch-pop")
  }

  hideMessage() {
    this.messageTarget.classList.add("hidden")
  }

  // A short note at the top of the scene.
  flash(text) {
    clearTimeout(this.toastTimer)
    this.toastTarget.textContent = text
    this.toastTarget.classList.remove("hidden")
    replay(this.toastTarget, "ch-pop")
    this.toastTimer = setTimeout(() => this.toastTarget.classList.add("hidden"), 2500)
  }

  name(id) {
    return this.nicknames[id] || "?"
  }

  // Keep the screen on while searching.
  async keepAwake() {
    if (!("wakeLock" in navigator)) return
    const request = async () => { try { this.wakeLock = await navigator.wakeLock.request("screen") } catch {} }
    this.onVisible = () => { if (document.visibilityState === "visible") request() }
    document.addEventListener("visibilitychange", this.onVisible)
    request()
  }
}
