import { Controller } from "@hotwired/stimulus"
import consumer from "channels/consumer"

// Bird drawn as a filled "M" silhouette using bezier curves
// Each bird moves independently — no flocking
// Background: painted sky gradient + fluffy clouds

const BIRD_COLOR        = "#1a1a2e"
const DISTRACTOR_COLORS = ["#e74c3c", "#e67e22", "#8e44ad", "#16a085", "#c0392b"]
const FPS               = 60
const FRAME_MS          = 1000 / FPS

let CLOUDS = []

export default class extends Controller {
  static values  = { roomCode: String }
  static targets = [
    "canvas",
    "phaseWaiting", "phaseShowing", "phaseReveal", "phaseGameOver",
    "countdown", "roundCounter", "roundCounter2", "difficultyBadge",
    "correctCount", "playerResults", "finalLeaderboard", "playAgain"
  ]

  connect() {
    this.birds       = []
    this.animFrame   = null
    this.timerHandle = null
    this.lastTime    = 0
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
      case "start_round":      this.onStartRound(data);      break
      case "player_submitted": this.onPlayerSubmitted(data);  break
      case "reveal":           this.onReveal(data);           break
      case "game_over":        this.onGameOver(data);         break
      case "game_restarted":   window.location.reload();      break
    }
  }

  // ── Message handlers ──────────────────────────────────────────────────────

  onStartRound(data) {
    const { round, total_rounds, bird_count, difficulty, distractor_count, duration } = data

    this.roundCounterTarget.textContent    = `Round ${round} / ${total_rounds}`
    this.roundCounter2Target.textContent   = `Round ${round} / ${total_rounds}`
    this.difficultyBadgeTarget.textContent = difficulty.toUpperCase()
    this.difficultyBadgeTarget.style.color = this.difficultyColor(difficulty)

    this.spawnBirds(bird_count, distractor_count, difficulty)
    this.startAnimation(difficulty)
    this.showPhase("phaseShowing")
    this.startCountdown(this.countdownTarget, duration)
  }

  onPlayerSubmitted(data) {
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

  // ── Bird spawning ─────────────────────────────────────────────────────────

  spawnBirds(birdCount, distractorCount, difficulty) {
    const canvas = this.canvasTarget
    const W      = canvas.offsetWidth  || window.innerWidth
    const H      = canvas.offsetHeight || window.innerHeight
    canvas.width  = W
    canvas.height = H

    this.birds = []
    this.generateClouds(W, H)

    for (let i = 0; i < birdCount; i++) {
      this.birds.push(this.createBird(W, H, difficulty, BIRD_COLOR, false))
    }

    for (let i = 0; i < distractorCount; i++) {
      const color = DISTRACTOR_COLORS[i % DISTRACTOR_COLORS.length]
      this.birds.push(this.createBird(W, H, difficulty, color, true))
    }
  }

  generateClouds(W, H) {
    CLOUDS = []
    const count = 6 + Math.floor(Math.random() * 5)
    for (let i = 0; i < count; i++) {
      CLOUDS.push({
        x:     Math.random() * W,
        y:     H * 0.05 + Math.random() * H * 0.55,
        scale: 0.6 + Math.random() * 1.2,
        puffs: Array.from({ length: 4 + Math.floor(Math.random() * 4) }, () => ({
          ox: (Math.random() - 0.5) * 90,
          oy: (Math.random() - 0.5) * 30,
          r:  28 + Math.random() * 30
        }))
      })
    }
  }

  createBird(W, H, difficulty, color, isDistractor) {
    const speed = difficulty === "chaos"  ? 1.5 + Math.random() * 2.0
                : difficulty === "moving" ? 0.7 + Math.random() * 1.0
                : 0

    const angle = Math.random() * Math.PI * 2
    return {
      x:           Math.random() * W,
      y:           Math.random() * H,
      vx:          Math.cos(angle) * speed,
      vy:          Math.sin(angle) * speed,
      size:        42 + Math.random() * 28,
      color,
      isDistractor,
      wingPhase:   Math.random() * Math.PI * 2,
      wingSpeed:   0.05 + Math.random() * 0.04,
      turnTimer:   0,
      turnEvery:   difficulty === "chaos" ? 60 + Math.floor(Math.random() * 90) : 9999
    }
  }

  // ── Animation loop ────────────────────────────────────────────────────────

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
      this.draw(ctx, canvas.width, canvas.height)
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
          b.turnTimer = 0
          b.turnEvery = 60 + Math.floor(Math.random() * 90)
          const spd   = Math.hypot(b.vx, b.vy)
          const angle = Math.random() * Math.PI * 2
          b.vx = Math.cos(angle) * spd
          b.vy = Math.sin(angle) * spd
        }
      }

      b.x += b.vx
      b.y += b.vy

      // Wrap edges
      if (b.x < -b.size)    b.x = W + b.size
      if (b.x > W + b.size) b.x = -b.size
      if (b.y < -b.size)    b.y = H + b.size
      if (b.y > H + b.size) b.y = -b.size
    }
  }

  // ── Drawing ───────────────────────────────────────────────────────────────

  draw(ctx, W, H) {
    // Sky gradient
    const sky = ctx.createLinearGradient(0, 0, 0, H)
    sky.addColorStop(0,   "#1a6fa8")
    sky.addColorStop(0.5, "#4ab3e8")
    sky.addColorStop(1,   "#b8e4f9")
    ctx.fillStyle = sky
    ctx.fillRect(0, 0, W, H)

    // Clouds
    ctx.fillStyle   = "rgba(255,255,255,0.88)"
    ctx.shadowColor = "rgba(200,230,255,0.5)"
    ctx.shadowBlur  = 18
    for (const c of CLOUDS) {
      ctx.save()
      ctx.translate(c.x, c.y)
      ctx.scale(c.scale, c.scale)
      for (const p of c.puffs) {
        ctx.beginPath()
        ctx.arc(p.ox, p.oy, p.r, 0, Math.PI * 2)
        ctx.fill()
      }
      ctx.restore()
    }
    ctx.shadowBlur = 0

    // Birds
    for (const b of this.birds) {
      this.drawBird(ctx, b)
    }
  }

  drawBird(ctx, b) {
    const flap = Math.sin(b.wingPhase) * b.size * 0.45

    ctx.save()
    ctx.translate(b.x, b.y)
    ctx.fillStyle   = b.color
    ctx.shadowColor = "rgba(0,0,0,0.45)"
    ctx.shadowBlur  = 6

    // Filled wing silhouette
    ctx.beginPath()
    ctx.moveTo(-b.size, 0)
    ctx.quadraticCurveTo(-b.size * 0.55, -flap, 0, 0)
    ctx.quadraticCurveTo( b.size * 0.55, -flap, b.size, 0)
    ctx.quadraticCurveTo( b.size * 0.55, flap * 0.15, 0, b.size * 0.08)
    ctx.quadraticCurveTo(-b.size * 0.55, flap * 0.15, -b.size, 0)
    ctx.closePath()
    ctx.fill()

    ctx.shadowBlur = 0
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
      if (this[key]) this[`${p}Target`].classList.toggle("hidden", p !== name)
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
