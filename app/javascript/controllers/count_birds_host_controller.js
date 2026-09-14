import { Controller } from "@hotwired/stimulus"
import consumer from "channels/consumer"

// Bird drawn as a simple "M" silhouette using canvas arcs
// Distractors are colored (non-black) shapes

const BIRD_COLOR       = "#000000"
const DISTRACTOR_COLORS = ["#e74c3c", "#3498db", "#2ecc71", "#9b59b6", "#f39c12"]
const FPS              = 60
const FRAME_MS         = 1000 / FPS

export default class extends Controller {
  static values  = { roomCode: String }
  static targets = [
    "canvas",
    "phaseWaiting", "phaseShowing", "phaseReveal", "phaseGameOver",
    "countdown", "roundCounter", "roundCounter2", "difficultyBadge",
    "correctCount", "playerResults", "finalLeaderboard", "playAgain"
  ]

  connect() {
    this.birds        = []
    this.animFrame    = null
    this.timerHandle  = null
    this.lastTime     = 0
    this.subscribe()
  }

  disconnect() {
    this.channel?.unsubscribe()
    clearInterval(this.timerHandle)
    cancelAnimationFrame(this.animFrame)
  }

  subscribe() {
    this.channel = consumer.subscriptions.create({
      channel:   "Games::CountBirdsChannel",
      room_code: this.roomCodeValue,
      player_id: ""
    }, {
      connected: () => {
        console.log("[CountBirds Host] connected — starting game loop")
        this.channel.perform("start_game_loop", {})
      },
      received: (data) => this.handleMessage(data)
    })
  }

  handleMessage(data) {
    console.log("[CountBirds Host] received", data.action, data)
    switch (data.action) {
      case "start_round":      this.onStartRound(data);     break
      case "player_submitted": this.onPlayerSubmitted(data); break
      case "reveal":           this.onReveal(data);          break
      case "game_over":        this.onGameOver(data);        break
      case "game_restarted":   window.location.reload();     break
    }
  }

  // ── Message handlers ──────────────────────────────────────────────────────

  onStartRound(data) {
    const { round, total_rounds, bird_count, difficulty, distractor_count, duration } = data

    this.roundCounterTarget.textContent  = `Round ${round} / ${total_rounds}`
    this.roundCounter2Target.textContent = `Round ${round} / ${total_rounds}`
    this.difficultyBadgeTarget.textContent = difficulty.toUpperCase()
    this.difficultyBadgeTarget.style.color = this.difficultyColor(difficulty)

    this.spawnBirds(bird_count, distractor_count, difficulty)
    this.startAnimation(difficulty)
    this.showPhase("phaseShowing")
    this.startCountdown(this.countdownTarget, duration)
  }

  onPlayerSubmitted(data) {
    // Could show a small indicator — keep simple for now
    console.log(`[CountBirds Host] ${data.nickname} submitted`)
  }

  onReveal(data) {
    clearInterval(this.timerHandle)
    this.stopAnimation()

    this.correctCountTarget.textContent = data.bird_count
    this.playerResultsTarget.innerHTML  = this.buildPlayerResults(data)

    this.showPhase("phaseReveal")
  }

  onGameOver(data) {
    this.finalLeaderboardTarget.innerHTML = this.buildLeaderboard(data)
    this.playAgainTarget.addEventListener("click", () => {
      this.channel.perform("restart_game", {})
    }, { once: true })

    this.showPhase("phaseGameOver")
  }

  // ── Bird animation ────────────────────────────────────────────────────────

  spawnBirds(birdCount, distractorCount, difficulty) {
    const canvas = this.canvasTarget
    const W      = canvas.offsetWidth  || window.innerWidth
    const H      = canvas.offsetHeight || window.innerHeight
    canvas.width  = W
    canvas.height = H

    this.birds = []

    // Real (black) birds
    for (let i = 0; i < birdCount; i++) {
      this.birds.push(this.createBird(W, H, difficulty, BIRD_COLOR, false))
    }

    // Distractors (colored)
    for (let i = 0; i < distractorCount; i++) {
      const color = DISTRACTOR_COLORS[i % DISTRACTOR_COLORS.length]
      this.birds.push(this.createBird(W, H, difficulty, color, true))
    }
  }

  createBird(W, H, difficulty, color, isDistractor) {
    const speed = difficulty === "chaos"  ? 1.5 + Math.random() * 2.5
                : difficulty === "moving" ? 0.8 + Math.random() * 1.2
                : 0  // static

    const angle = Math.random() * Math.PI * 2
    return {
      x:           Math.random() * W,
      y:           Math.random() * H,
      vx:          Math.cos(angle) * speed,
      vy:          Math.sin(angle) * speed,
      size:        14 + Math.random() * 10,
      color,
      isDistractor,
      wingPhase:   Math.random() * Math.PI * 2,
      wingSpeed:   0.08 + Math.random() * 0.06,
      turnTimer:   0,
      turnEvery:   difficulty === "chaos" ? 40 + Math.floor(Math.random() * 60) : 9999
    }
  }

  startAnimation(difficulty) {
    this.stopAnimation()
    const canvas = this.canvasTarget
    const ctx    = canvas.getContext("2d")

    const loop = (ts) => {
      if (ts - this.lastTime < FRAME_MS) {
        this.animFrame = requestAnimationFrame(loop)
        return
      }
      this.lastTime = ts
      this.updateBirds(canvas.width, canvas.height, difficulty)
      this.drawBirds(ctx, canvas.width, canvas.height)
      this.animFrame = requestAnimationFrame(loop)
    }

    this.animFrame = requestAnimationFrame(loop)
  }

  stopAnimation() {
    cancelAnimationFrame(this.animFrame)
    this.animFrame = null
  }

  updateBirds(W, H, difficulty) {
    for (const b of this.birds) {
      b.wingPhase += b.wingSpeed

      if (difficulty === "chaos") {
        b.turnTimer++
        if (b.turnTimer >= b.turnEvery) {
          b.turnTimer  = 0
          b.turnEvery  = 40 + Math.floor(Math.random() * 60)
          const angle  = Math.random() * Math.PI * 2
          const spd    = Math.hypot(b.vx, b.vy)
          b.vx = Math.cos(angle) * spd
          b.vy = Math.sin(angle) * spd
        }
      }

      b.x += b.vx
      b.y += b.vy

      // Wrap edges
      if (b.x < -b.size)  b.x = W + b.size
      if (b.x > W + b.size) b.x = -b.size
      if (b.y < -b.size)  b.y = H + b.size
      if (b.y > H + b.size) b.y = -b.size
    }
  }

  drawBirds(ctx, W, H) {
    ctx.clearRect(0, 0, W, H)

    for (const b of this.birds) {
      this.drawBird(ctx, b)
    }
  }

  drawBird(ctx, b) {
    // Wing flap: offset from base position using sin
    const flap = Math.sin(b.wingPhase) * b.size * 0.35

    ctx.save()
    ctx.translate(b.x, b.y)
    ctx.fillStyle   = b.color
    ctx.strokeStyle = b.color
    ctx.lineWidth   = b.size * 0.18

    // Two arcs: left wing and right wing ("M" silhouette)
    ctx.beginPath()
    // Left wing
    ctx.moveTo(0, 0)
    ctx.quadraticCurveTo(-b.size * 0.6, -flap, -b.size, 0)
    // Right wing
    ctx.moveTo(0, 0)
    ctx.quadraticCurveTo(b.size * 0.6, -flap, b.size, 0)
    ctx.stroke()

    ctx.restore()
  }

  // ── Countdown ─────────────────────────────────────────────────────────────

  startCountdown(el, seconds) {
    clearInterval(this.timerHandle)
    let remaining = seconds
    el.textContent = remaining

    this.timerHandle = setInterval(() => {
      remaining -= 1
      el.textContent = remaining
      if (remaining <= 0) clearInterval(this.timerHandle)
    }, 1000)
  }

  // ── HTML builders ─────────────────────────────────────────────────────────

  buildPlayerResults(data) {
    const { picks, round_scores, nicknames } = data
    return Object.entries(round_scores || {})
      .sort((a, b) => b[1] - a[1])
      .map(([id, pts]) => {
        const name  = nicknames?.[id] || id
        const guess = picks?.[id] ?? "—"
        const color = pts >= 100 ? "text-green-400" : pts > 0 ? "text-yellow-400" : "text-slate-500"
        return `
          <div class="bg-black/50 rounded-xl px-4 py-2 text-center min-w-[90px]">
            <p class="text-white text-xs font-mono truncate max-w-[80px]">${this.esc(name)}</p>
            <p class="text-white font-black text-2xl">${guess}</p>
            <p class="${color} text-xs font-bold">+${pts} pts</p>
          </div>`
      }).join("")
  }

  buildLeaderboard(data) {
    const { scores, nicknames } = data
    const medals = ["🥇", "🥈", "🥉"]
    return Object.entries(scores || {})
      .sort((a, b) => b[1] - a[1])
      .map(([id, pts], i) => {
        const name  = nicknames?.[id] || id
        const medal = medals[i] || `#${i + 1}`
        return `
          <div class="flex items-center justify-between bg-slate-800 rounded-xl px-5 py-3">
            <span class="text-2xl w-8">${medal}</span>
            <span class="flex-1 text-white font-bold ml-3 truncate">${this.esc(name)}</span>
            <span class="font-mono font-black text-yellow-400 text-lg">${pts}</span>
          </div>`
      }).join("")
  }

  // ── Helpers ───────────────────────────────────────────────────────────────

  showPhase(name) {
    const phases = ["phaseWaiting", "phaseShowing", "phaseReveal", "phaseGameOver"]
    phases.forEach(p => {
      const key = `has${p.charAt(0).toUpperCase() + p.slice(1)}Target`
      if (this[key]) {
        this[`${p}Target`].classList.toggle("hidden", p !== name)
      }
    })
  }

  difficultyColor(difficulty) {
    return difficulty === "chaos"  ? "#ef4444"
         : difficulty === "moving" ? "#f59e0b"
         : "#94a3b8"
  }

  esc(str) {
    return String(str).replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;")
  }
}
