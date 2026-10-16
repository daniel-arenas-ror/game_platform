import { Controller } from "@hotwired/stimulus"
import consumer from "channels/consumer"
import { t } from "controllers/shared/i18n"
import { confetti } from "controllers/shared/celebration"
import { startCountdown, stopCountdown, Sounds } from "controllers/haunted_house/common"
import { drawMonster, injectMonsterStyles } from "controllers/monster_mash/monster"

// The TV. The server sends the public state on every phase change ("state"); monsters arrive one
// at a time at the reveal ("monster") and all together from the vote on ("gallery"). The TV never
// sees a drawing before the reveal.
export default class extends Controller {
  static values  = { roomCode: String }
  static targets = [
    "soundButton", "story", "icon", "kicker", "headline", "subline",
    "reveal", "revealMonster", "revealCount", "revealName", "revealArtists",
    "grid", "progress", "countdown", "skipButton",
    "phaseGameOver", "gameOverTitle", "gameOverHint", "finalScores", "gallery"
  ]

  connect() {
    injectMonsterStyles()
    this.sounds    = new Sounds()
    this.state     = null
    this.nicknames = {}
    this.monsters  = {}   // index → monster with its drawings
    this.progress  = []
    this.soundLabel = this.soundButtonTarget.textContent.trim().replace(/^\S+\s*/, "")
    this.unlockSound = () => this.sounds.unlock()
    document.addEventListener("pointerdown", this.unlockSound)

    this.channel = consumer.subscriptions.create(
      { channel: "Games::MonsterMashChannel", room_code: this.roomCodeValue, player_id: "" },
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
      case "monster":        this.onMonster(data.monster); break
      case "gallery":        this.onGallery(data.monsters); break
      case "progress":       this.progress = data.ids || []; this.renderProgress(); break
      case "player_left":    this.channel.perform("sync", {}); break
      case "game_restarted": window.location.reload(); break
      case "game_changed":   window.location.href = `/rooms/${this.roomCodeValue}`; break
      case "game_error":     this.setStory("💥", "", t("monster_mash.error"), ""); break
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
    const previous = this.state?.phase
    this.state     = state
    this.nicknames = nicknames || {}
    this.progress  = state.done_ids || state.voted_ids || []
    const changed  = previous !== state.phase

    this.revealTarget.classList.add("hidden")
    this.gridTarget.classList.add("hidden")
    this.storyTarget.classList.remove("hidden")
    this.skipButtonTarget.classList.add("hidden")
    this.progressTarget.textContent = ""

    switch (state.phase) {
      case "theme":   this.setStory("🎃", t("monster_mash.theme_label"), state.theme, ""); break
      case "drawing": this.showDrawing(); break
      case "passing": this.showPassing(); break
      case "reveal":  this.showReveal(); break
      case "vote":    this.showVote(changed); break
      case "results": this.showResults(changed); break
      case "game_over": this.showGameOver(changed); break
      default:        this.setStory("🧟", "", this.headlineTarget.textContent, state.theme || "")
    }

    if (state.phase === "game_over") stopCountdown(this.countdownTarget)
    else startCountdown(this.countdownTarget, state.seconds_left)
  }

  showDrawing() {
    const part = t(`monster_mash.parts.${this.state.part}`)
    this.setStory(t(`monster_mash.part_icons.${this.state.part}`), this.state.theme,
                  t("monster_mash.tv_draw_title", { part }), t("monster_mash.tv_draw_hint"))
    this.renderProgress()
  }

  showPassing() {
    const next = ["head", "body", "legs"][(this.state.round ?? -1) + 1] || "legs"
    this.setStory("↪️", this.state.theme, t("monster_mash.passing_title"),
                  t("monster_mash.passing_hint", { part: t(`monster_mash.parts.${next}`) }))
  }

  showReveal() {
    const index = this.state.reveal_index
    if (index >= 0 && this.monsters[index]) this.renderReveal(this.monsters[index], false)
    else this.setStory("🥁", this.state.theme, "…", "")
  }

  onMonster(monster) {
    if (!monster) return
    this.monsters[monster.index] = monster
    if (this.state?.phase === "reveal") this.renderReveal(monster, true)
  }

  // The monster drops in part by part to a drumroll, then its name and artists appear.
  renderReveal(monster, animate) {
    this.storyTarget.classList.add("hidden")
    this.revealTarget.classList.remove("hidden")
    this.skipButtonTarget.disabled = false
    this.skipButtonTarget.classList.remove("hidden")
    this.revealCountTarget.textContent = t("monster_mash.reveal_title", { index: monster.index + 1, total: this.state.monsters_count })
    this.revealNameTarget.textContent    = ""
    this.revealArtistsTarget.textContent = ""

    const step = animate ? 1400 : 0
    if (animate) this.sounds.drumroll(step * 3 / 1000)
    drawMonster(this.revealMonsterTarget, monster, { animate, stepMs: step })
    setTimeout(() => {
      this.revealNameTarget.textContent = monster.name
      this.revealNameTarget.classList.remove("mm-pop"); void this.revealNameTarget.offsetWidth
      this.revealNameTarget.classList.add("mm-pop")
      this.revealArtistsTarget.textContent = this.artistsLine(monster)
    }, step * 3)
  }

  showVote(changed) {
    this.setStory("🗳️", "", t("monster_mash.vote_title"), "")
    this.renderGrid()
    this.renderProgress()
    if (changed) this.sounds.drumroll(1.5)
  }

  showResults(changed) {
    const results = this.state.results || {}
    const top     = results.top || []
    const names   = top.map(i => this.state.monsters[i]?.name).filter(Boolean)
    this.setStory("🏆", t("monster_mash.monster_of_night"), names.join(" · ") || t("monster_mash.no_votes"), "")
    this.renderGrid(results.tally || {}, top)
    this.skipButtonTarget.disabled = false
    this.skipButtonTarget.classList.remove("hidden")
    if (changed && top.length) { this.sounds.chime(); confetti() }
  }

  showGameOver(changed) {
    const winners = this.state.results?.winners || []
    this.gameOverTitleTarget.textContent = t("monster_mash.game_over")
    this.gameOverHintTarget.textContent  = winners.length
      ? t("monster_mash.winners", { names: winners.map(id => this.name(id)).join(", ") }) : ""

    const scores = Object.entries(this.state.scores || {}).sort((a, b) => b[1] - a[1])
    this.finalScoresTarget.replaceChildren(...scores.map(([id, points]) => {
      const row = document.createElement("div")
      row.className = `flex justify-between rounded-xl px-4 py-2 font-bold ${winners.includes(id) ? "bg-green-500/20 text-green-200" : "bg-slate-800"}`
      const name = document.createElement("span")
      name.textContent = this.name(id)
      const pts = document.createElement("span")
      pts.className = "tabular-nums"
      pts.textContent = points
      row.append(name, pts)
      return row
    }))
    this.phaseGameOverTarget.classList.remove("hidden")
    this.renderGallery()
    if (changed) { this.sounds.chime(); confetti() }
  }

  onGallery(monsters) {
    (monsters || []).forEach(m => { if (m) this.monsters[m.index] = m })
    if (["vote", "results"].includes(this.state?.phase)) this.onState({ state: this.state, nicknames: this.nicknames })
    if (this.state?.phase === "game_over") this.renderGallery()
  }

  // ── Rendering ─────────────────────────────────────────────────────────────

  setStory(icon, kicker, headline, subline) {
    this.phaseGameOverTarget.classList.add("hidden")
    this.iconTarget.classList.remove("hidden")
    this.iconTarget.textContent     = icon
    this.kickerTarget.textContent   = kicker || ""
    this.headlineTarget.textContent = headline || ""
    this.sublineTarget.textContent  = subline || ""
  }

  // Every monster, small, with its name (and votes at the results). The top ones are highlighted.
  renderGrid(tally = null, top = []) {
    this.iconTarget.classList.add("hidden") // room for the monsters
    this.gridTarget.classList.remove("hidden")
    this.gridTarget.replaceChildren(...this.cards(tally, top))
  }

  renderGallery() {
    this.galleryTarget.replaceChildren(...this.cards(this.state?.results?.tally || {}, this.state?.results?.top || []))
  }

  cards(tally, top) {
    const count = this.state?.monsters_count || 0
    return Array.from({ length: count }, (_, i) => {
      const card = document.createElement("figure")
      card.className = `w-40 lg:w-44 rounded-2xl p-2 ${top.includes(i) ? "bg-green-500/20 ring-4 ring-green-400" : "bg-slate-900/80"}`
      const art = document.createElement("div")
      card.append(art)
      if (this.monsters[i]) drawMonster(art, this.monsters[i])
      const caption = document.createElement("figcaption")
      caption.className = "mt-2 text-sm font-bold leading-tight"
      caption.textContent = this.state.monsters?.[i]?.name || ""
      card.append(caption)
      if (tally) {
        const votes = document.createElement("p")
        votes.className = "text-green-300 text-sm font-bold"
        votes.textContent = t("monster_mash.votes", { count: tally[i] || 0 })
        card.append(votes)
      }
      return card
    })
  }

  renderProgress() {
    if (!this.state || !["drawing", "vote"].includes(this.state.phase)) return
    const total = Object.keys(this.nicknames).length
    const done  = this.progress.length
    const key   = this.state.phase === "drawing" ? "monster_mash.done_count" : "monster_mash.voted_count"
    this.progressTarget.textContent = t(key, { done, total })
  }

  artistsLine(monster) {
    const a = monster.artists || {}
    return t("monster_mash.artists", { head: this.name(a.head), body: this.name(a.body), legs: this.name(a.legs) })
  }

  name(id) {
    return this.nicknames[id] || t("monster_mash.nobody")
  }
}
