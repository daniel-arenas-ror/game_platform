import { Controller } from "@hotwired/stimulus"
import consumer from "channels/consumer"
import { t } from "controllers/shared/i18n"
import { celebrateWin } from "controllers/shared/celebration"
import { PALETTE, ERASER, BRUSH_SIZES, fitCanvas, clearCanvas, createPen, redraw } from "controllers/doodle_dash/drawing"
import { startCountdown, stopCountdown } from "controllers/haunted_house/common"
import { drawMonster, injectMonsterStyles } from "controllers/monster_mash/monster"

const MIN_STEP     = 0.002 // canvas fractions: smaller moves are skipped
const STROKE_LIMIT = 1000  // points per stroke (the server's max); longer lines continue as a new stroke
const PANELS       = ["panelMessage", "panelDraw", "panelVote", "panelGallery"]

// A phone. Draws its part each round (the strokes go to the server one by one, never to the TV),
// then votes. The server sends this phone's view of every phase ("state"), with its task while
// drawing; monsters arrive at the reveal ("monster") and all together from the vote on ("gallery").
export default class extends Controller {
  static values  = { roomCode: String, playerId: String }
  static targets = [
    "countdown", "status", ...PANELS, "messageIcon", "messageTitle", "messageHint",
    "drawTitle", "drawHint", "guideBox", "guide", "canvas", "colors", "sizes", "doneButton",
    "voteTitle", "voteGrid", "phaseGameOver", "gameOverTitle", "gameOverHint"
  ]

  connect() {
    injectMonsterStyles()
    this.state     = null
    this.nicknames = {}
    this.monsters  = {}
    this.task      = null  // { monster, part, guide, strokes, done } while drawing
    this.strokes   = []
    this.lastId    = 0
    this.pointerId = null
    this.color     = PALETTE[0]
    this.size      = BRUSH_SIZES[1]

    this.renderTools()
    this.keepAwake()
    this.onResize = () => this.fitDrawing()
    window.addEventListener("resize", this.onResize)

    this.channel = consumer.subscriptions.create(
      { channel: "Games::MonsterMashChannel", room_code: this.roomCodeValue, player_id: this.playerIdValue },
      {
        rejected: () => window.location.reload(),
        received: (data) => this.handleMessage(data)
      }
    )
  }

  disconnect() {
    window.removeEventListener("resize", this.onResize)
    document.removeEventListener("visibilitychange", this.onVisible)
    stopCountdown(this.countdownTarget)
    this.wakeLock?.release().catch(() => {})
    this.channel?.unsubscribe()
  }

  handleMessage(data) {
    switch (data.action) {
      case "state":          this.onState(data); break
      case "monster":        if (data.monster) this.monsters[data.monster.index] = data.monster; break
      case "gallery":        this.onGallery(data.monsters); break
      case "done_ok":        this.showDoneWait(); break
      case "voted":          if (this.state) { this.state.my_vote = data.index; this.renderVote() } break
      case "player_left":    this.channel.perform("sync", {}); break
      case "game_restarted": window.location.reload(); break
      case "game_changed":   window.location.href = `/rooms/${this.roomCodeValue}`; break
    }
  }

  // ── State ─────────────────────────────────────────────────────────────────

  onState({ state, nicknames }) {
    const previous = this.state?.phase
    this.state     = state
    this.nicknames = nicknames || {}
    this.statusTarget.textContent = state.theme || ""

    if (state.phase === "game_over") stopCountdown(this.countdownTarget)
    else startCountdown(this.countdownTarget, state.seconds_left)

    switch (state.phase) {
      case "theme":
        this.message("🎃", state.theme, t("monster_mash.theme_label")); break
      case "drawing":
        this.startDrawing(state.assignment); break
      case "passing": {
        const next = ["head", "body", "legs"][(state.round ?? -1) + 1] || "legs"
        this.message("↪️", t("monster_mash.passing_title"), t("monster_mash.passing_hint", { part: t(`monster_mash.parts.${next}`) }))
        break
      }
      case "vote":
        this.renderVote(); break
      case "results":
        this.showResults(); break
      case "game_over":
        if (previous !== "game_over") this.showGameOver()
        break
      default:
        this.message("📺", this.element.dataset.lookTv, state.theme || "")
    }
  }

  onGallery(monsters) {
    (monsters || []).forEach(m => { if (m) this.monsters[m.index] = m })
    if (this.state?.phase === "vote") this.renderVote()
    if (!this.panelGalleryTarget.classList.contains("hidden")) this.showGallery()
  }

  // ── Drawing ───────────────────────────────────────────────────────────────

  startDrawing(task) {
    if (!task) return this.message("📺", this.element.dataset.lookTv, "")
    const sameTask = this.task && this.task.monster === task.monster && this.task.part === task.part
    this.task = task
    if (task.done) return this.showDoneWait()

    if (!sameTask) {
      // A new part: the strokes the server already has (after a reload), ids after them.
      this.strokes = task.strokes || []
      this.lastId  = Math.max(0, ...this.strokes.map(s => s.id))
    }
    const part = t(`monster_mash.parts.${task.part}`)
    this.drawTitleTarget.textContent = `${t(`monster_mash.part_icons.${task.part}`)} ${t("monster_mash.draw_the", { part })}`
    this.drawHintTarget.textContent  = t(`monster_mash.draw_hint_${task.part}`)
    this.guideBoxTarget.classList.toggle("hidden", !task.guide)
    this.doneButtonTarget.disabled = false
    this.show("panelDraw")
    requestAnimationFrame(() => this.fitDrawing())
  }

  fitDrawing() {
    if (this.panelDrawTarget.classList.contains("hidden")) return
    fitCanvas(this.canvasTarget)
    redraw(this.canvasTarget, this.strokes)
    if (this.task?.guide) {
      fitCanvas(this.guideTarget)
      redraw(this.guideTarget, this.task.guide)
    }
  }

  done() {
    if (!this.task) return
    this.endStroke()
    this.doneButtonTarget.disabled = true
    this.channel.perform("done", {})
  }

  showDoneWait() {
    this.message("✅", t("monster_mash.done_wait"), this.state?.theme || "")
  }

  penDown(event) {
    if (!this.task || this.task.done || this.pointerId !== null) return
    event.preventDefault()
    this.canvasTarget.setPointerCapture(event.pointerId)
    this.pointerId = event.pointerId
    this.startStroke(this.pointFrom(event))
  }

  startStroke(point) {
    this.stroke = { id: ++this.lastId, color: this.color, size: this.size, points: [point] }
    this.pen    = createPen(this.canvasTarget, this.color, this.size)
    this.pen.add([point])
    this.last   = point
  }

  penMove(event) {
    if (event.pointerId !== this.pointerId) return
    event.preventDefault()
    const events = event.getCoalescedEvents?.() || [event]
    events.forEach(e => {
      const point = this.pointFrom(e)
      if (Math.hypot(point[0] - this.last[0], point[1] - this.last[1]) < MIN_STEP) return
      this.pen.add([point])
      this.last = point
      this.stroke.points.push(point)
      if (this.stroke.points.length >= STROKE_LIMIT) { this.finishStroke(); this.startStroke(point) }
    })
  }

  penUp(event) {
    if (event.pointerId !== this.pointerId) return
    this.endStroke()
  }

  endStroke() {
    if (this.pointerId === null) return
    this.finishStroke()
    this.pointerId = null
    this.stroke = null
  }

  // Each finished stroke is saved on the server at once, so nothing is lost when time runs out.
  finishStroke() {
    this.pen.end()
    this.channel.perform("stroke_end", this.stroke)
    this.strokes.push(this.stroke)
  }

  pointFrom(event) {
    const rect  = this.canvasTarget.getBoundingClientRect()
    const clamp = v => Math.round(Math.min(Math.max(v, 0), 1) * 10000) / 10000
    return [clamp((event.clientX - rect.left) / rect.width), clamp((event.clientY - rect.top) / rect.height)]
  }

  undo() {
    if (!this.strokes.length) return
    const { id } = this.strokes.pop()
    redraw(this.canvasTarget, this.strokes)
    this.channel.perform("undo", { id })
  }

  clear() {
    if (!this.strokes.length) return
    this.strokes = []
    clearCanvas(this.canvasTarget)
    this.channel.perform("clear", { upto: this.lastId })
  }

  renderTools() {
    this.colorsTarget.replaceChildren(...PALETTE.map(color => {
      const button = document.createElement("button")
      button.type = "button"
      button.dataset.color = color
      button.setAttribute("aria-label", color === ERASER ? t("monster_mash.eraser") : t("monster_mash.color", { color }))
      button.className = "size-10 rounded-full border-2 border-slate-600 cursor-pointer grid place-items-center text-lg"
      button.style.background = color
      button.textContent = color === ERASER ? "🧽" : ""
      button.addEventListener("click", () => { this.color = color; this.markTools() })
      return button
    }))
    this.sizesTarget.replaceChildren(...BRUSH_SIZES.map(size => {
      const button = document.createElement("button")
      button.type = "button"
      button.dataset.size = size
      button.setAttribute("aria-label", t("monster_mash.brush", { size }))
      button.className = "size-12 rounded-xl bg-slate-800 border-2 border-slate-700 cursor-pointer grid place-items-center"
      const dot = document.createElement("span")
      dot.className = "block rounded-full bg-white"
      dot.style.width = dot.style.height = `${4 + size * 0.8}px`
      button.append(dot)
      button.addEventListener("click", () => { this.size = size; this.markTools() })
      return button
    }))
    this.markTools()
  }

  markTools() {
    this.colorsTarget.querySelectorAll("[data-color]").forEach(btn => {
      const on = btn.dataset.color === this.color
      btn.classList.toggle("ring-4", on)
      btn.classList.toggle("ring-green-400", on)
      btn.setAttribute("aria-pressed", on)
    })
    this.sizesTarget.querySelectorAll("[data-size]").forEach(btn => {
      const on = Number(btn.dataset.size) === this.size
      btn.classList.toggle("border-green-400", on)
      btn.classList.toggle("border-slate-700", !on)
      btn.setAttribute("aria-pressed", on)
    })
  }

  // ── Vote, results, the end ────────────────────────────────────────────────

  // Every monster as a card; the one this phone started can't be voted for.
  renderVote() {
    const s = this.state
    if (!s || s.phase !== "vote") return
    if (s.my_vote != null) {
      return this.message("🗳️", t("monster_mash.you_voted", { name: s.monsters?.[s.my_vote]?.name || "" }), "")
    }

    this.voteTitleTarget.textContent = t("monster_mash.vote_for")
    this.voteGridTarget.replaceChildren(...(s.monsters || []).map((monster, i) => {
      const mine   = i === s.my_monster && s.monsters.length > 1
      const button = document.createElement("button")
      button.type = "button"
      button.disabled = mine
      button.className = `rounded-2xl p-2 text-left transition-transform active:scale-95 ${mine ? "opacity-40" : "bg-slate-900/80 border-2 border-slate-700 cursor-pointer"}`
      const art  = document.createElement("div")
      const name = document.createElement("p")
      name.className = "mt-2 text-sm font-bold leading-tight"
      name.textContent = mine ? `${monster.name} (${t("monster_mash.yours")})` : monster.name
      button.append(art, name)
      button.addEventListener("click", () => {
        this.voteGridTarget.querySelectorAll("button").forEach(b => { b.disabled = true })
        this.channel.perform("vote", { index: i })
      })
      if (this.monsters[i]) requestAnimationFrame(() => drawMonster(art, this.monsters[i]))
      return button
    }))
    this.show("panelVote")
  }

  showResults() {
    const results = this.state.results || {}
    const names   = (results.top || []).map(i => this.state.monsters[i]?.name).filter(Boolean)
    const points  = this.state.scores?.[this.playerIdValue] ?? 0
    this.message("🏆", names.length ? `${t("monster_mash.monster_of_night")}: ${names.join(" · ")}` : t("monster_mash.no_votes"),
                 t("monster_mash.your_points", { count: points }))
  }

  showGameOver() {
    const winners = this.state.results?.winners || []
    const points  = this.state.scores?.[this.playerIdValue] ?? 0
    const won     = winners.includes(this.playerIdValue)
    this.gameOverTitleTarget.textContent = won ? t("monster_mash.you_win") : t("monster_mash.game_over")
    this.gameOverHintTarget.textContent  = t("monster_mash.your_points", { count: points })
    this.phaseGameOverTarget.classList.remove("hidden")
    if (won) celebrateWin(this.gameOverTitleTarget)
  }

  // Every monster, to screenshot a favourite.
  showGallery() {
    this.phaseGameOverTarget.classList.add("hidden")
    const count = this.state?.monsters_count || 0
    if (Object.keys(this.monsters).length < count) this.channel.perform("gallery", {})
    this.show("panelGallery")
    this.panelGalleryTarget.replaceChildren(...Array.from({ length: count }, (_, i) => {
      const figure = document.createElement("figure")
      figure.className = "rounded-2xl bg-slate-900/80 p-2"
      const art = document.createElement("div")
      figure.append(art)
      const caption = document.createElement("figcaption")
      caption.className = "mt-2 text-sm font-bold leading-tight"
      caption.textContent = this.state.monsters?.[i]?.name || ""
      figure.append(caption)
      if (this.monsters[i]) requestAnimationFrame(() => drawMonster(art, this.monsters[i]))
      return figure
    }))
  }

  // ── Helpers ───────────────────────────────────────────────────────────────

  message(icon, title, hint = "") {
    this.messageIconTarget.textContent  = icon
    this.messageTitleTarget.textContent = title || ""
    this.messageHintTarget.textContent  = hint || ""
    this.show("panelMessage")
  }

  show(panel) {
    PANELS.forEach(p => this[`${p}Target`].classList.toggle("hidden", p !== panel))
  }

  // Keep the screen on: a phone that dims mid-drawing loses its part.
  async keepAwake() {
    if (!("wakeLock" in navigator)) return
    const request = async () => { try { this.wakeLock = await navigator.wakeLock.request("screen") } catch {} }
    this.onVisible = () => { if (document.visibilityState === "visible") request() }
    document.addEventListener("visibilitychange", this.onVisible)
    request()
  }
}
