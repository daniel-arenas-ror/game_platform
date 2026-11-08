import { Controller } from "@hotwired/stimulus"
import consumer from "channels/consumer"
import { celebrateWin, isTopScore, pop } from "controllers/shared/celebration"
import { t, num } from "controllers/shared/i18n"
import { escapeHtml } from "controllers/shared/html"
import { avatarHtml } from "controllers/shared/avatar"
import { soundFile } from "controllers/shared/sound"

const SUSPENSE_MS  = 1500 // answer counts on screen before the right answer lights up
const STANDINGS_MS = 1300 // then the standings slide into their new order (TV)

export default class extends Controller {
  static targets = [
    "loading",
    "question",
    "input",
    "bet",
    "reveal",
    "leaderboard",
    // question / input shared
    "questionText",
    "questionMeta",
    "optionA", "optionB", "optionC", "optionD",
    "lockedMessage",
    "lockLabel",
    "countdown",          // array — host + player
    // reveal section
    "revealRoundLabel",
    "revealOption",       // array — 4 elements
    "revealOptionText",   // array — 4 elements
    "revealOptionIcon",   // array — 4 elements
    "revealOptionCount",  // array — 4 elements: how many picked it
    "revealPlayerResult",
    "revealResultText",
    "revealTotalText",
    "revealRankText",
    "revealLeader",
    "revealHostScores",
    "nextInfo",
    "nextButton",
    // bets (final question) and 50:50
    "betProgress", "betPoints", "betOptions", "betStatus",
    "fiftyButton",
    // leaderboard
    "leaderboardList",
    "awards"
  ]

  static values = { status: String, roomCode: String, playerId: String }

  connect() {
    this.answered       = false
    this.selectedOption = null
    this.timerHandle    = null
    this.revealTimers   = []
    this.calm           = window.matchMedia?.("(prefers-reduced-motion: reduce)").matches
    this.clickingSound  = soundFile("/games/sounds/clicking.mp3")
    this.chooseSound    = soundFile("/games/sounds/choose.mp3")
    this.clickingSound.loop = true
    this.updateVisibility()
    this.subscribe()
  }

  disconnect() {
    this.winSound?.pause()
    this.stopCountdown()
    this.clearRevealTimers()
    clearInterval(this.nextHandle)
    this.channel?.unsubscribe()
  }

  statusValueChanged() {
    this.updateVisibility()
  }

  updateVisibility() {
    const s = this.statusValue
    this.loadingTarget.classList.toggle("hidden",     s !== "loading")
    this.questionTarget.classList.toggle("hidden",    s !== "question")
    this.inputTarget.classList.toggle("hidden",       s !== "input")
    this.betTarget.classList.toggle("hidden",         s !== "bet")
    this.revealTarget.classList.toggle("hidden",      s !== "reveal")
    this.leaderboardTarget.classList.toggle("hidden", s !== "leaderboard")
  }

  // ── Player taps an answer ─────────────────────────────────────────────────

  selectOption(event) {
    if (this.answered) return
    this.chooseSound.currentTime = 0
    this.chooseSound.play().catch(() => {}) // ignore autoplay blocks
    this.lockChoice(event.currentTarget)
    this.channel.perform("submit_millionaire_answer", { choice: this.selectedOption })
  }

  // Marks the picked answer: it stays bright, the others fade, nothing can be tapped any more.
  lockChoice(picked) {
    this.answered       = true
    this.selectedOption = parseInt(picked.dataset.option, 10)

    this.optionButtons().forEach(btn => {
      btn.classList.replace("border-yellow-400", "border-blue-800")
      btn.disabled = true
      btn.classList.add("cursor-not-allowed")
      if (btn !== picked) btn.classList.add("opacity-40")
    })
    picked.classList.replace("border-blue-800", "border-yellow-400")

    if (this.hasLockedMessageTarget) this.lockedMessageTarget.classList.remove("hidden")
    if (this.hasLockLabelTarget)     this.lockLabelTarget.classList.add("hidden")
  }

  // 1.234 → "1.2" (or "1,2" in Spanish)
  seconds(value) {
    return num(Math.round(value * 10) / 10)
  }

  // "🔥 3 in a row", plus "×1.5" once the streak pays extra.
  streakLabel(streak, multiplier) {
    return multiplier > 1
      ? t("how_want_be_billionare.streak_bonus", { count: streak, multiplier: num(multiplier) })
      : t("how_want_be_billionare.streak", { count: streak })
  }

  // ── Host: Play Again ──────────────────────────────────────────────────────

  restartGame(event) {
    event.currentTarget.disabled = true
    this.channel.perform("restart_game", {})
  }

  // ── Subscribe ─────────────────────────────────────────────────────────────

  subscribe() {
    this.channel = consumer.subscriptions.create({
      channel:   "Games::MillionaireChannel",
      room_code: this.roomCodeValue,
      player_id: this.playerIdValue
    }, {
      connected: () => {
        if (this.statusValue === "loading" && this.playerIdValue === "") {
          this.channel.perform("start_game_loop", {})
        }
      },
      rejected: () => window.location.reload(),   // removed after a long disconnect → server sends us to /join
      received: (data) => this.handleMessage(data)
    })
  }

  handleMessage(data) {
    switch (data.action) {
      case "send_question":    this.onSendQuestion(data);   break
      case "place_bets":       this.onPlaceBets(data);      break
      case "bet_placed":       this.onBetPlaced(data);      break
      case "bets_progress":    this.onBetsProgress(data);   break
      case "fifty_fifty":      this.applyFifty(data.removed); break
      case "reveal_answer":    this.onRevealAnswer(data);   break
      case "show_leaderboard": this.onShowLeaderboard(data); break
      case "player_presence":  break
      case "game_restarted":   window.location.reload();    break
      case "game_changed":     window.location.href = `/rooms/${this.roomCodeValue}`; break
      default: console.warn("[Millionaire] unhandled action:", data.action)
    }
  }

  // ── Message handlers ──────────────────────────────────────────────────────

  onSendQuestion(data) {
    this.hideNext()
    // Reset round state
    this.answered       = false
    this.selectedOption = null

    this.optionButtons().forEach(btn => {
      btn.disabled = false
      btn.classList.remove("opacity-40", "opacity-10", "cursor-not-allowed", "border-yellow-400")
      btn.classList.add("border-blue-800")
    })
    if (data.fifty_used) this.fiftyUsed = true
    if (this.hasFiftyButtonTarget) this.fiftyButtonTarget.classList.toggle("hidden", !!this.fiftyUsed)
    if (this.hasLockedMessageTarget) this.lockedMessageTarget.classList.add("hidden")
    if (this.hasLockLabelTarget)     this.lockLabelTarget.classList.remove("hidden")

    // Populate question text (targets appear in both host and player sections)
    const roundLabel = t("how_want_be_billionare.round", { round: data.round, total: data.total })
    const worth      = data.points ? ` · ${t("how_want_be_billionare.worth", { points: num(data.points) })}` : ""
    const finalLabel = t("how_want_be_billionare.final_question")
    this.questionTextTargets.forEach(el => { el.textContent = data.text })
    this.questionMetaTargets.forEach(el => {
      el.textContent = (data.final ? finalLabel : roundLabel) + worth
      el.classList.toggle("text-yellow-400", !!data.final)
      el.classList.toggle("text-blue-400", !data.final)
    })
    if (this.hasLockLabelTarget) {
      this.lockLabelTarget.textContent = data.final ? finalLabel : t("how_want_be_billionare.lock_in")
    }

    const labels = [this.optionATarget, this.optionBTarget, this.optionCTarget, this.optionDTarget]
    data.options.forEach((opt, i) => { labels[i].textContent = opt.text })

    this.statusValue = this.playerIdValue === "" ? "question" : "input"
    this.startCountdown(data.duration)

    // Reconnected after answering this question (sent with the current screen on connect).
    const picked = [...this.optionButtons()].find(btn => parseInt(btn.dataset.option, 10) === data.my_choice)
    if (data.fifty_removed) this.applyFifty(data.fifty_removed)
    if (picked) this.lockChoice(picked)
  }

  // ── 50:50 (once per game, this phone only) ────────────────────────────────

  useFifty() {
    if (this.fiftyUsed || this.answered) return
    this.fiftyUsed = true
    this.fiftyButtonTarget.classList.add("hidden")
    this.channel.perform("use_fifty", {})
  }

  applyFifty(removed) {
    this.fiftyUsed = true
    if (this.hasFiftyButtonTarget) this.fiftyButtonTarget.classList.add("hidden")
    this.optionButtons().forEach(btn => {
      if (!removed.includes(parseInt(btn.dataset.option, 10))) return
      btn.disabled = true
      btn.classList.add("opacity-10", "cursor-not-allowed")
    })
  }

  // ── Bets before the final question ────────────────────────────────────────

  onPlaceBets(data) {
    this.hideNext()
    this.clearRevealTimers()
    this.statusValue = "bet"
    this.startCountdown(data.duration)

    if (this.playerIdValue === "") {
      this.onBetsProgress({ placed: 0 })
      return
    }

    const mine = data.points?.[this.playerIdValue] || 0
    this.betStatusTarget.classList.add("hidden")
    this.betOptionsTarget.innerHTML = ""
    if (mine <= 0) {
      this.betPointsTarget.textContent = t("how_want_be_billionare.nothing_to_bet")
      return
    }

    this.betPointsTarget.textContent = t("how_want_be_billionare.you_have", { points: num(mine) })
    data.fractions.forEach(fraction => {
      const amount = Math.round(mine * fraction / 10) * 10
      const button = document.createElement("button")
      button.type = "button"
      button.dataset.fraction = fraction
      button.dataset.action = "millionaire#placeBet"
      button.className = "rounded-2xl border-2 border-blue-800 bg-blue-950 py-5 px-3 text-lg font-black active:scale-95 transition-transform" +
                         (fraction === 1 ? " border-yellow-400 text-yellow-300" : "")
      button.textContent = fraction === 0 ? t("how_want_be_billionare.bet_none")
                         : fraction === 1 ? t("how_want_be_billionare.bet_all", { points: num(amount) })
                         : t("how_want_be_billionare.bet_share", { percent: num(fraction * 100), points: num(amount) })
      this.betOptionsTarget.appendChild(button)
    })
    if (data.my_bet != null) this.onBetPlaced({ amount: data.my_bet })
  }

  placeBet(event) {
    this.betOptionsTarget.querySelectorAll("button").forEach(b => { b.disabled = true; b.classList.add("opacity-40") })
    event.currentTarget.classList.remove("opacity-40")
    this.channel.perform("place_bet", { fraction: parseFloat(event.currentTarget.dataset.fraction) })
  }

  onBetPlaced({ amount }) {
    if (!this.hasBetStatusTarget) return
    this.betOptionsTarget.innerHTML = ""
    this.betStatusTarget.textContent = t("how_want_be_billionare.bet_placed", { points: num(amount) })
    this.betStatusTarget.classList.remove("hidden")
  }

  onBetsProgress({ placed }) {
    if (this.hasBetProgressTarget) this.betProgressTarget.textContent = t("how_want_be_billionare.bets_in", { count: placed })
  }

  // The reveal comes in three beats: how many picked each answer (everyone guesses), then the
  // right answer with each player's points, then (TV) the standings sliding into their new order.
  onRevealAnswer(data) {
    this.stopCountdown()
    this.showNext(data)
    this.clearRevealTimers()
    const { options, round, total } = data

    this.revealRoundLabelTarget.textContent = t("how_want_be_billionare.round_reveal", { round, total })
    this.revealOptionTextTargets.forEach((el, i) => { el.textContent = options[i]?.text || "" })
    this.paintTiles(null, data.answer_counts)
    this.revealPlayerResultTarget.classList.add("hidden")
    this.revealHostScoresTarget.classList.add("hidden")
    this.revealLeaderTarget.classList.add("hidden")
    this.statusValue = "reveal"

    this.revealTimers.push(setTimeout(() => this.showRoundResult(data), SUSPENSE_MS))
  }

  clearRevealTimers() {
    ;(this.revealTimers || []).forEach(clearTimeout)
    this.revealTimers = []
  }

  // correct: the right answer indices, or null while it's still a secret (my own pick stays lit).
  paintTiles(correct, counts) {
    this.revealOptionTargets.forEach((el, i) => {
      const picked    = i === this.selectedOption
      const isCorrect = correct?.includes(i)
      const isMyWrong = correct && picked && !isCorrect
      const icon      = this.revealOptionIconTargets[i]

      if (!correct) {
        el.style.borderColor     = picked ? "#facc15" : "#334155"
        el.style.backgroundColor = "transparent"
        el.style.opacity         = "1"
        icon.textContent         = ""
      } else {
        el.style.borderColor     = isCorrect ? "#4ade80" : (isMyWrong ? "#f87171" : "#334155")
        el.style.backgroundColor = isCorrect ? "rgba(21,128,61,0.15)" : (isMyWrong ? "rgba(153,27,27,0.15)" : "transparent")
        el.style.opacity         = (!isCorrect && !isMyWrong) ? "0.35" : "1"
        icon.textContent         = isCorrect ? "✓" : (isMyWrong ? "✗" : "")
        icon.style.color         = isCorrect ? "#4ade80" : "#f87171"
        if (isCorrect && !this.calm) el.animate([ { transform: "scale(1.04)" }, { transform: "scale(1)" } ], { duration: 350 })
      }

      const count = counts?.[i] ?? 0
      this.revealOptionCountTargets[i].textContent = counts ? t("how_want_be_billionare.picked", { count }) : ""
    })
  }

  showRoundResult(data) {
    const { correct_answer_indices, round_scores, user_points, nicknames } = data
    const details = data.round_details || {}
    const streaks = data.streaks || {}
    this.paintTiles(correct_answer_indices, data.answer_counts)

    if (this.playerIdValue !== "") {
      // ── Player view: their own result and where they stand ──────────────
      const myId     = this.playerIdValue
      const earned   = round_scores[myId] || 0
      const myTotal  = user_points[myId]  || 0
      const correct  = earned > 0
      const mine     = details[myId] || {}
      const lostRun  = !correct && (this.myStreak || 0) >= 2
      const bet      = mine.bet || 0
      this.myStreak  = streaks[myId] || 0

      this.revealPlayerResultTarget.classList.remove("hidden")

      this.revealResultTextTarget.textContent = correct
        ? t("how_want_be_billionare.correct", { points: num(earned) })
        : t("how_want_be_billionare.incorrect")
      this.revealResultTextTarget.style.color = correct ? "#4ade80" : "#f87171"
      // Speed and streak on one line, the total on the next.
      const extras = []
      if (correct && mine.seconds != null) extras.push(t("how_want_be_billionare.answered_in", { seconds: this.seconds(mine.seconds) }))
      if (correct && mine.streak >= 2) extras.push(this.streakLabel(mine.streak, mine.multiplier))
      if (lostRun) extras.push(t("how_want_be_billionare.streak_lost"))
      if (bet > 0) extras.push(t("how_want_be_billionare.bet_won", { points: num(bet) }))
      if (bet < 0) extras.push(t("how_want_be_billionare.bet_lost", { points: num(-bet) }))
      const total = t("how_want_be_billionare.running_total", { points: num(myTotal) })
      this.revealTotalTextTarget.textContent = extras.length ? `${extras.join(" · ")}\n${total}` : total
      this.revealRankTextTarget.textContent  = this.rankLine(myId, user_points, nicknames)
    } else {
      // ── Host view: everyone's round, in the old order first ─────────────
      const before = data.previous_points || user_points
      const order  = (points) => Object.keys(nicknames).sort((a, b) => (points[b] || 0) - (points[a] || 0))
      this.revealHostScoresTarget.innerHTML = order(before).map(pid => this.hostRow(pid, data, details, streaks)).join("")
      this.revealHostScoresTarget.classList.remove("hidden")
      this.revealTimers.push(setTimeout(() => this.moveStandings(order(user_points), before, user_points, data.new_leader, nicknames), STANDINGS_MS))
    }
  }

  hostRow(pid, { nicknames, round_scores, user_points }, details, streaks) {
    const avatar   = avatarHtml(nicknames[pid] || pid, "size-8 shrink-0")
    const name     = escapeHtml(nicknames[pid] || pid)
    const earned   = round_scores[pid] || 0
    const runTotal = user_points[pid] || 0
    const scored   = earned > 0
    const info     = details[pid] || {}
    const fire     = (streaks[pid] || 0) >= 2
      ? `<span class="text-orange-400 font-black">🔥${streaks[pid]}</span>` : ""
    const speed    = scored && info.seconds != null
      ? `<span class="text-slate-500 ml-2">${this.seconds(info.seconds)} s</span>` : ""
    const bonus    = info.multiplier > 1 ? `<span class="text-orange-400 ml-1">×${num(info.multiplier)}</span>` : ""
    const bet      = info.bet
      ? `<span class="ml-2 ${info.bet > 0 ? "text-yellow-300" : "text-red-400"}">🎲${info.bet > 0 ? "+" : "−"}${num(Math.abs(info.bet))}</span>` : ""

    return `
      <div data-pid="${escapeHtml(pid)}" class="flex items-center justify-between p-3 rounded-xl border
                  ${scored ? "border-green-700/50 bg-green-900/10" : "border-slate-800 bg-slate-900/30"}">
        <span class="flex items-center gap-2 min-w-0 font-bold text-sm ${scored ? "text-green-300" : "text-slate-500"}">${avatar}<span class="truncate">${name}</span>${fire}<span data-move class="font-mono text-xs"></span></span>
        <div class="text-right font-mono text-xs">
          <span class="${scored ? "text-green-400 font-black" : "text-slate-600"}">
            ${scored ? "+" + num(earned) : "+0"}
          </span>${bonus}${bet}${speed}
          <span class="text-slate-600 ml-2">${t("how_want_be_billionare.total", { points: num(runTotal) })}</span>
        </div>
      </div>
    `
  }

  // Rows slide to their new places (FLIP), with ↑2 / ↓1 next to the names and a banner for a new leader.
  moveStandings(newOrder, before, after, leaderId, nicknames) {
    const list = this.revealHostScoresTarget
    const rows = new Map([...list.children].map(row => [row.dataset.pid, row]))
    const tops = new Map([...rows].map(([pid, row]) => [pid, row.getBoundingClientRect().top]))
    const rank = (points, pid) => 1 + Object.values(points).filter(p => (p || 0) > (points[pid] || 0)).length

    newOrder.forEach(pid => rows.get(pid) && list.appendChild(rows.get(pid)))
    rows.forEach((row, pid) => {
      const moved = rank(before, pid) - rank(after, pid)
      const badge = row.querySelector("[data-move]")
      badge.textContent = moved > 0 ? `↑${moved}` : (moved < 0 ? `↓${-moved}` : "")
      badge.style.color = moved > 0 ? "#4ade80" : "#f87171"

      const dy = tops.get(pid) - row.getBoundingClientRect().top
      if (dy && !this.calm) {
        row.animate([ { transform: `translateY(${dy}px)` }, { transform: "translateY(0)" } ],
                    { duration: 650, easing: "cubic-bezier(.2,.8,.2,1)" })
      }
    })

    if (leaderId && nicknames[leaderId]) {
      this.revealLeaderTarget.textContent = t("how_want_be_billionare.takes_lead", { name: nicknames[leaderId] })
      this.revealLeaderTarget.classList.remove("hidden")
      if (!this.calm) pop(this.revealLeaderTarget)
    }
  }

  // "#1 · 40 pts ahead", "#1 · tied for the lead" or "#3 · 120 pts behind Ana" (the player just above).
  rankLine(myId, points, nicknames) {
    const mine   = points[myId] || 0
    const others = Object.keys(nicknames).filter(id => id !== myId)
    const above  = others.filter(id => (points[id] || 0) > mine)
    if (!others.length) return ""

    if (!above.length) {
      const next = Math.max(...others.map(id => points[id] || 0))
      return next === mine
        ? t("how_want_be_billionare.rank_tied_lead")
        : t("how_want_be_billionare.rank_lead", { points: num(mine - next) })
    }
    const closest = above.reduce((a, b) => ((points[a] || 0) <= (points[b] || 0) ? a : b))
    return t("how_want_be_billionare.rank_behind", {
      rank: above.length + 1, points: num((points[closest] || 0) - mine), name: nicknames[closest]
    })
  }

  onShowLeaderboard(data) {
    this.hideNext()
    this.stopCountdown()
    if (!this.playerIdValue) {
      this.winSound = soundFile("/games/sounds/Triumphant_win.mp3")
      this.winSound.play().catch(() => {}) // ignore autoplay blocks
    }
    const { leaderboard, nicknames } = data
    const medals = ["🥇", "🥈", "🥉"]

    this.leaderboardListTarget.innerHTML = Object.entries(leaderboard).map(([playerId, points], index) => {
      const nickname = (nicknames && nicknames[playerId]) || t("how_want_be_billionare.player", { n: index + 1 })
      const name  = escapeHtml(nickname)
      const isTop = index === 0
      const medal = medals[index] || `#${index + 1}`

      return `
        <div class="flex items-center justify-between
                    ${isTop
                      ? "bg-gradient-to-r from-yellow-500/20 via-slate-900 to-slate-900 border border-yellow-500/40 shadow-lg shadow-yellow-500/5"
                      : "bg-slate-900/80 border border-blue-900/50"}
                    p-4 rounded-2xl">
          <div class="flex items-center space-x-4">
            <span class="text-xl font-black ${isTop ? "text-yellow-400" : "text-slate-500"}">${medal}</span>
            ${avatarHtml(nickname, "size-10")}
            <span class="font-bold ${isTop ? "text-slate-100" : "text-slate-300"}">${name}</span>
          </div>
          <span class="font-mono ${isTop
            ? "bg-yellow-400 text-slate-950 font-black"
            : "bg-blue-950 border border-blue-800 text-blue-400 font-bold"}
            px-4 py-1 rounded-full text-sm">${num(points)}</span>
        </div>
      `
    }).join("")

    this.renderAwards(data.awards || [], nicknames || {})
    this.statusValue = "leaderboard"
    if (this.playerIdValue && isTopScore(leaderboard, this.playerIdValue)) celebrateWin()
  }

  // ── Countdown ─────────────────────────────────────────────────────────────

  startCountdown(seconds) {
    this.stopCountdown()
    if (!seconds) return

    let remaining = seconds
    this.renderCountdown(remaining)

    // Host only: looping tension sound while players answer
    if (this.playerIdValue === "") {
      this.clickingSound.currentTime = 0
      this.clickingSound.play().catch(() => {}) // ignore autoplay blocks
    }

    this.timerHandle = setInterval(() => {
      remaining -= 1
      this.renderCountdown(Math.max(remaining, 0))
      if (remaining <= 0) this.stopCountdown()
    }, 1000)
  }

  stopCountdown() {
    clearInterval(this.timerHandle)
    this.timerHandle = null
    this.clickingSound?.pause()
  }

  renderCountdown(remaining) {
    this.countdownTargets.forEach(el => {
      el.textContent = remaining
      el.classList.toggle("text-yellow-400", remaining > 5)
      el.classList.toggle("text-red-500",    remaining <= 5)
    })
  }

  renderAwards(awards, nicknames) {
    const details = {
      fastest:  (a) => t("how_want_be_billionare.award_fastest_detail", { seconds: this.seconds(a.seconds) }),
      streak:   (a) => t("how_want_be_billionare.award_streak_detail", { count: a.count }),
      comeback: (a) => t("how_want_be_billionare.award_comeback_detail", { from: a.from, to: a.to })
    }
    const shown = awards.filter(a => details[a.key] && nicknames[a.player_id])
    this.awardsTarget.classList.toggle("hidden", !shown.length)
    this.awardsTarget.innerHTML = shown.length ? `
      <p class="text-center text-xs font-bold uppercase tracking-widest text-blue-400">${t("how_want_be_billionare.awards")}</p>
      ${shown.map(a => `
        <div class="flex items-center gap-3 rounded-2xl border border-slate-700 bg-slate-900/80 p-3">
          ${avatarHtml(nicknames[a.player_id], "size-9 shrink-0")}
          <div class="min-w-0 flex-1">
            <p class="text-sm font-black text-yellow-300">${t(`how_want_be_billionare.award_${a.key}`)}</p>
            <p class="truncate font-bold text-slate-200">${escapeHtml(nicknames[a.player_id])}</p>
          </div>
          <span class="font-mono text-sm text-slate-400">${details[a.key](a)}</span>
        </div>`).join("")}` : ""
  }

  // ── Next question: countdown ("auto") or the host's button ("manual") ────

  showNext({ advance, next_in, last }) {
    this.hideNext()
    const isHost = this.playerIdValue === ""

    if (advance === "manual") {
      if (isHost && this.hasNextButtonTarget) {
        this.nextButtonTarget.textContent = t(last ? "how_want_be_billionare.show_results" : "how_want_be_billionare.next_question")
        this.nextButtonTarget.disabled = false
        this.nextButtonTarget.classList.remove("hidden")
      } else {
        this.setNextInfo(t("how_want_be_billionare.waiting_host"))
      }
    } else if (next_in) {
      let remaining = next_in
      const key = last ? "how_want_be_billionare.results_in" : "how_want_be_billionare.next_in"
      this.setNextInfo(t(key, { seconds: remaining }))
      this.nextHandle = setInterval(() => {
        remaining -= 1
        if (remaining > 0) this.setNextInfo(t(key, { seconds: remaining }))
        else clearInterval(this.nextHandle)
      }, 1000)
    }
  }

  hideNext() {
    clearInterval(this.nextHandle)
    if (this.hasNextInfoTarget) this.nextInfoTarget.classList.add("hidden")
    if (this.hasNextButtonTarget) this.nextButtonTarget.classList.add("hidden")
  }

  setNextInfo(text) {
    if (!this.hasNextInfoTarget) return
    this.nextInfoTarget.textContent = text
    this.nextInfoTarget.classList.remove("hidden")
  }

  // Host taps Next: the server sends the next question (or the results).
  nextQuestion() {
    this.nextButtonTarget.disabled = true
    this.channel.perform("next_question", {})
  }

  // ── Helpers ───────────────────────────────────────────────────────────────

  optionButtons() {
    return this.element.querySelectorAll('[data-action="click->millionaire#selectOption"]')
  }
}
