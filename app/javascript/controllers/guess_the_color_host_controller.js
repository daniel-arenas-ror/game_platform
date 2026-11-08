import { Controller } from "@hotwired/stimulus"
import consumer from "channels/consumer"
import { t } from "controllers/shared/i18n"
import { escapeHtml } from "controllers/shared/html"
import { avatarHtml } from "controllers/shared/avatar"
import { soundFile } from "controllers/shared/sound"
import { confetti, pop } from "controllers/shared/celebration"

export default class extends Controller {
  static values  = { roomCode: String }
  static targets = [
    "phaseWaiting", "phaseShowing", "phasePicking", "phaseReveal", "phaseGameOver",
    "colorBlock", "showingTimer", "pickingTimer", "submittedList",
    "revealGrid", "roundScores", "finalLeaderboard", "roundCounter", "playAgain",
    "showingLabel", "pickingColor", "pickingPrompt", "revealPrompt", "awards"
  ]

  connect() {
    this.state       = null
    this.timerHandle = null
    this.tickSound   = soundFile("/games/sounds/timer_count_down.mp3")
    this.winSound    = soundFile("/games/sounds/Triumphant_win.mp3")
    this.dingSound   = soundFile("/games/sounds/reveal.mp3")
    this.revealTimers = []
    this.calm        = window.matchMedia?.("(prefers-reduced-motion: reduce)").matches
    this.subscribe()
  }

  disconnect() {
    this.channel?.unsubscribe()
    this.stopTimer()
    this.revealTimers.forEach(clearTimeout)
    this.winSound.pause()
  }

  // ── ActionCable ───────────────────────────────────────────────────────────

  subscribe() {
    this.channel = consumer.subscriptions.create({
      channel:   "Games::GuessTheColorChannel",
      room_code: this.roomCodeValue,
      player_id: ""
    }, {
      connected: () => {
        console.log("[GuessTheColor Host] channel connected — starting game loop")
        this.channel.perform("start_game_loop", {})
      },
      received: (data) => this.handleMessage(data)
    })
  }

  handleMessage(data) {
    switch (data.action) {
      case "state_snapshot":   this.applySnapshot(data.state); break
      case "show_color":       this.showColor(data);           break
      case "start_picking":    this.startPicking(data);        break
      case "player_submitted": this.markSubmitted(data);       break
      case "reveal":           this.showReveal(data);          break
      case "game_over":        this.showGameOver(data);        break
      case "game_restarted":   window.location.reload();       break
      case "game_changed":     window.location.href = `/rooms/${this.roomCodeValue}`; break
    }
  }

  // ── Phase handlers ────────────────────────────────────────────────────────

  applySnapshot(state) {
    this.state = state
    // Restore correct phase if host refreshes mid-game
    switch (state?.status) {
      case "showing_color": this.showPhase("phaseShowing"); break
      case "picking":       this.showPhase("phasePicking"); break
      case "revealing":     this.showPhase("phaseReveal");  break
      case "game_over":     this.showPhase("phaseGameOver"); break
      default:              this.showPhase("phaseWaiting");
    }
  }

  showColor(data) {
    this.stopTimer()
    this.showPhase("phaseShowing")

    // Real-world mode names a thing instead of showing a colour.
    const mode = data.prompt ? "real_world" : (data.mode || "memory")
    this.showingLabelTarget.textContent = t(`guess_the_color.showing.${mode}`)
    if (data.prompt) {
      this.colorBlockTarget.style.background = "#1e293b"
      this.colorBlockTarget.textContent = data.prompt
    } else {
      const { r, g, b } = data.color
      this.colorBlockTarget.style.background = `rgb(${r},${g},${b})`
      this.colorBlockTarget.textContent = ""
    }

    this.updateRoundCounter(data.round, data.total_rounds)
    this.startCountdown(this.showingTimerTarget, data.duration)
  }

  startPicking(data) {
    this.stopTimer()
    this.showPhase("phasePicking")

    if (this.hasSubmittedListTarget) this.submittedListTarget.innerHTML = ""
    this.pickingColorTarget.classList.toggle("hidden", !data.color)
    if (data.color) this.pickingColorTarget.style.background = `rgb(${data.color.r},${data.color.g},${data.color.b})`
    this.pickingPromptTarget.classList.toggle("hidden", !data.prompt)
    this.pickingPromptTarget.textContent = data.prompt || ""
    this.updateRoundCounter(data.round, data.total_rounds)
    this.startCountdown(this.pickingTimerTarget, data.duration)
  }

  markSubmitted(data) {
    if (!this.hasSubmittedListTarget) return
    const pill = document.createElement("span")
    pill.className = "bg-slate-700 text-slate-300 text-xs font-bold px-3 py-1 rounded-full"
    pill.textContent = data.nickname
    this.submittedListTarget.appendChild(pill)
  }

  // The target first, then everyone's colour from the furthest to the closest, one every
  // `step_ms`; then the closest gets the trophy and the round's scores come up.
  showReveal(data) {
    this.stopTimer()
    this.revealTimers.forEach(clearTimeout)
    this.revealTimers = []
    this.showPhase("phaseReveal")
    this.updateRoundCounter(data.round, data.total_rounds)
    this.revealPromptTarget.classList.toggle("hidden", !data.prompt)
    this.revealPromptTarget.textContent = data.prompt || ""

    const matches = data.matches || {}
    const missing = Object.keys(data.scores).filter(id => !data.picks[id])
    const ranked  = Object.keys(data.picks).sort((a, b) => (matches[a] ?? 0) - (matches[b] ?? 0))
    const step    = this.calm ? 0 : (data.step_ms ?? 500)
    const { r, g, b } = data.target_color

    this.revealGridTarget.innerHTML = this.colorCard(`rgb(${r},${g},${b})`, t("guess_the_color.target"), true, false, null,
                                                     data.perfect, this.colorName(data.target_name))
    this.roundScoresTarget.innerHTML = ""

    const cards = [
      ...missing.map(id => this.colorCard("rgb(30,30,30)", t("guess_the_color.no_pick", { name: this.nicknameFor(id, data) }), false, true)),
      ...ranked.map(id => {
        const { r, g, b } = data.picks[id]
        return this.colorCard(`rgb(${r ?? 128},${g ?? 128},${b ?? 128})`, this.nicknameFor(id, data), false, false,
                              matches[id], data.perfect, this.colorName(data.pick_names?.[id]), id)
      })
    ]
    cards.forEach((html, i) => this.revealTimers.push(setTimeout(() => {
      this.revealGridTarget.insertAdjacentHTML("beforeend", html)
      const card = this.revealGridTarget.lastElementChild
      if (!this.calm) card.animate([ { opacity: 0, transform: "scale(.6)" }, { opacity: 1, transform: "scale(1)" } ], { duration: 300, easing: "ease-out" })
    }, (i + 1) * step)))

    this.revealTimers.push(setTimeout(() => this.finishReveal(data, ranked.at(-1)), (cards.length + 1) * step + 200))
  }

  finishReveal(data, closestId) {
    const card = closestId && this.revealGridTarget.querySelector(`[data-player="${closestId}"]`)
    if (card) {
      card.querySelector("[data-swatch]").classList.add("ring-4", "ring-yellow-400")
      card.insertAdjacentHTML("afterbegin", `<p class="text-yellow-300 font-black text-sm mb-1">${t("guess_the_color.closest")}</p>`)
      if (!this.calm) { pop(card); confetti(40) }
      this.dingSound.currentTime = 0
      this.dingSound.play().catch(() => {})
    }
    this.renderRoundScores(data)
  }

  renderRoundScores(data) {
    const sorted = Object.entries(data.scores).sort(([, a], [, b]) => b - a)
    this.roundScoresTarget.innerHTML = sorted.map(([playerId, total]) => {
      const nickname = this.nicknameFor(playerId, data)
      const roundPts = data.round_scores[playerId] ?? 0
      const bonus    = data.bonuses?.[playerId]
        ? `<span class="text-orange-400 text-xs font-black ml-2">${t("guess_the_color.streak_bonus", { count: data.streaks[playerId], points: data.bonuses[playerId] })}</span>` : ""
      return `
        <div class="flex items-center justify-between py-2 px-4 bg-slate-800 rounded-xl">
          <div class="flex items-center gap-2 min-w-0">
            ${avatarHtml(nickname, "size-7")}
            <span class="font-bold text-white text-sm truncate">${escapeHtml(nickname)}</span>${bonus}
          </div>
          <div class="text-right">
            <span class="text-yellow-400 font-mono font-black text-lg">${total}</span>
            <span class="text-slate-500 text-xs font-mono ml-2">(+${roundPts})</span>
          </div>
        </div>`
    }).join("")
  }

  // 🦅 Eagle eye, 🎯 Bullseye, 🌈 Most creative, each with its winner's avatar.
  renderAwards(awards, data) {
    this.awardsTarget.classList.toggle("hidden", !awards.length)
    this.awardsTarget.innerHTML = awards.length ? `
      <p class="text-center text-xs font-bold uppercase tracking-widest text-slate-400">${t("guess_the_color.awards")}</p>
      ${awards.map(a => {
        const name = this.nicknameFor(a.player_id, data)
        return `
          <div class="flex items-center gap-3 rounded-xl border border-slate-700 bg-slate-900 p-3">
            ${avatarHtml(name, "size-9 shrink-0")}
            <div class="min-w-0 flex-1">
              <p class="text-sm font-black text-yellow-300">${t(`guess_the_color.award_${a.key}`)}</p>
              <p class="truncate font-bold text-white">${escapeHtml(name)}</p>
            </div>
            <span class="font-mono text-sm text-slate-400">${t(`guess_the_color.award_${a.key}_detail`, { value: a.value })}</span>
          </div>`
      }).join("")}` : ""
  }

  colorName(key) {
    return key ? t(`guess_the_color.colors.${key}`) : ""
  }

  showGameOver(data) {
    this.stopTimer()
    this.showPhase("phaseGameOver")
    this.winSound.play().catch(() => {}) // ignore autoplay blocks

    if (this.hasFinalLeaderboardTarget) {
      const sorted = Object.entries(data.scores).sort(([, a], [, b]) => b - a)
      const medals = ["🥇", "🥈", "🥉"]
      this.finalLeaderboardTarget.innerHTML = sorted.map(([playerId, score], idx) => {
        const nickname = this.nicknameFor(playerId, data)
        const medal    = medals[idx] ?? `${idx + 1}.`
        return `
          <div class="flex items-center justify-between py-2 px-4 bg-slate-800 rounded-xl
                      ${idx === 0 ? "border border-yellow-500/50" : ""}">
            <div class="flex items-center gap-3">
              <span class="text-xl">${medal}</span>
              ${avatarHtml(nickname, "size-10")}
              <span class="font-bold text-white">${escapeHtml(nickname)}</span>
            </div>
            <span class="text-yellow-400 font-mono font-black text-xl">${score}</span>
          </div>`
      }).join("")
    }

    this.renderAwards(data.awards || [], data)

    if (this.hasPlayAgainTarget && !this.playAgainTarget._wired) {
      this.playAgainTarget._wired = true
      this.playAgainTarget.addEventListener("click", () => {
        this.channel?.perform("restart_game", {})
      })
    }
  }

  // ── Helpers ───────────────────────────────────────────────────────────────

  showPhase(targetName) {
    const allPhases = ["phaseWaiting", "phaseShowing", "phasePicking", "phaseReveal", "phaseGameOver"]
    allPhases.forEach(name => {
      const el = this[`has${name.charAt(0).toUpperCase() + name.slice(1)}Target`]
        ? this[`${name}Target`]
        : null
      if (el) el.classList.toggle("hidden", name !== targetName)
    })
  }

  startCountdown(el, seconds) {
    if (!el) return
    let remaining = seconds
    el.textContent = remaining
    this.playTick()
    this.timerHandle = setInterval(() => {
      remaining--
      el.textContent = remaining > 0 ? remaining : ""
      if (remaining > 0) this.playTick()
      else this.stopTimer()
    }, 1000)
  }

  playTick() {
    this.tickSound.currentTime = 0
    this.tickSound.play().catch(() => {}) // ignore autoplay blocks
  }

  stopTimer() {
    clearInterval(this.timerHandle)
    this.timerHandle = null
    this.tickSound?.pause()
  }

  updateRoundCounter(round, total) {
    if (this.hasRoundCounterTarget)
      this.roundCounterTarget.textContent = t("shared.round_of", { round, total })
  }

  // match: the pick's % match ("🎯" at `perfect` or more), shown under the name; colorName: the
  // nearest named colour ("Salmon").
  colorCard(bg, label, isTarget, dimmed = false, match = null, perfect = 97, colorName = "", playerId = "") {
    const border  = isTarget ? "border-2 border-yellow-400" : "border border-slate-700"
    const opacity = dimmed ? "opacity-40" : ""
    const color   = match >= 85 ? "text-green-400" : match >= 60 ? "text-yellow-400" : "text-red-400"
    const score   = match == null ? "" :
      `<p class="font-mono font-black text-lg ${color}">${match >= perfect ? "🎯 " : ""}${match}%</p>`
    return `
      <div class="text-center ${opacity}" data-player="${escapeHtml(playerId)}">
        <div data-swatch class="w-28 h-28 rounded-2xl shadow-lg ${border}"
             style="background:${bg}"></div>
        <p class="text-xs font-bold mt-2 text-slate-300 max-w-[112px] truncate">${escapeHtml(label)}</p>
        ${colorName ? `<p class="text-xs text-slate-500 italic max-w-[112px] truncate">${escapeHtml(colorName)}</p>` : ""}
        ${score}
      </div>`
  }

  // Look up a player's nickname from the room's player list.
  // Falls back to a shortened ID if not found (e.g. mid-game reconnect).
  nicknameFor(playerId, data) {
    return data.nicknames?.[playerId] ?? `#${playerId.slice(-4)}`
  }
}
