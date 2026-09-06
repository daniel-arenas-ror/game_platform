import { Controller } from "@hotwired/stimulus"
import consumer from "channels/consumer"
import { Application, Graphics, Container } from "pixi.js"

const WALL_COLORS  = { brick: 0xc0392b, steel: 0x7f8c8d, water: 0x2471a3, trees: 0x1e8449 }
const TANK_COLORS  = { yellow: 0xf1c40f, green: 0x2ecc71, white: 0xecf0f1, red: 0xe74c3c }
const BASE_COLOR   = { alive: 0xf39c12, dead: 0x4a4a4a }
const BULLET_COLOR = 0xffffff
const BG_COLOR     = 0x0d0d1a

// Explosion palette: yellow → orange → red as age increases
const EXP_COLORS = [0xffd700, 0xffa500, 0xff6600, 0xcc3300]

function darkenColor(hex, factor = 0.55) {
  const r = Math.round(((hex >> 16) & 0xff) * factor)
  const g = Math.round(((hex >>  8) & 0xff) * factor)
  const b = Math.round(( hex        & 0xff) * factor)
  return (r << 16) | (g << 8) | b
}

export default class extends Controller {
  static values = { roomCode: String }

  async connect() {
    this.state      = null
    this.pixiReady  = false
    this.explosions = []   // [{x, y, age, maxAge, color}]

    this.app = new Application()
    await this.app.init({
      width:      520,
      height:     520,
      background: BG_COLOR,
      antialias:  false
    })

    this.element.appendChild(this.app.canvas)

    // Two render layers: game content below, effects (explosions) above
    this.gameLayer = new Container()
    this.fxLayer   = new Container()
    this.app.stage.addChild(this.gameLayer)
    this.app.stage.addChild(this.fxLayer)

    // Explosion ticker — runs independently of server updates
    this.app.ticker.add(() => this.animateFX())

    this.pixiReady = true
    if (this.state) this.render()

    this.subscribe()
  }

  disconnect() {
    this.channel?.unsubscribe()
    this.app?.destroy(true)
    this.pixiReady = false
  }

  // ── ActionCable ──────────────────────────────────────────────────────────

  subscribe() {
    this.channel = consumer.subscriptions.create({
      channel:   "Games::BattleCityChannel",
      room_code: this.roomCodeValue,
      player_id: ""
    }, {
      connected: () => {
        console.log("[BattleCity] host connected — starting game loop")
        this.channel.perform("start_game_loop", { room_code: this.roomCodeValue })
      },
      received: (data) => this.handleMessage(data)
    })
  }

  handleMessage(data) {
    switch (data.action) {
      case "state_snapshot":
        this.state = data.state
        if (this.pixiReady) this.render()
        break

      case "state_delta":
        this.applyDelta(data.delta)
        break

      case "countdown":
        this.showCountdown(data.count)
        break

      case "game_over":
        this.showGameOver(data)
        break

      case "game_restarted":
        window.location.reload()
        break
    }
  }

  applyDelta(delta) {
    if (!this.state) return

    if (delta.tanks) {
      Object.entries(delta.tanks).forEach(([pid, newTank]) => {
        const prev = this.state.tanks[pid]
        // Detect kill — spawn explosion at last known position
        if (prev?.alive && !newTank.alive) {
          this.spawnExplosion(prev.x, prev.y, prev.color)
        }
      })
      Object.assign(this.state.tanks, delta.tanks)
    }

    if (delta.bullets)         this.state.bullets = delta.bullets
    if (delta.walls_destroyed) {
      delta.walls_destroyed.forEach(k => {
        // Small flash at destroyed brick position
        const [x, y] = k.split(",").map(Number)
        this.spawnExplosion(x, y, null)   // null color → brick dust
        delete this.state.walls[k]
      })
    }
    if (delta.scores) {
      Object.assign(this.state.scores, delta.scores)
      this.updateScoreboard(delta.scores)
    }

    if (this.pixiReady) this.render()
  }

  updateScoreboard(scores) {
    Object.entries(scores).forEach(([playerId, score]) => {
      const el = document.getElementById(`score-${playerId}`)
      if (el) el.textContent = score
    })
  }

  // ── Explosions ───────────────────────────────────────────────────────────

  spawnExplosion(x, y, tankColor) {
    this.explosions.push({
      x,
      y,
      age:    0,
      maxAge: tankColor ? 22 : 10,   // tank kill → longer; brick → short flash
      color:  tankColor ? (TANK_COLORS[tankColor] ?? 0xffffff) : 0xc0392b
    })
  }

  animateFX() {
    if (!this.explosions.length) {
      if (this.fxLayer.children.length) this.fxLayer.removeChildren()
      return
    }

    this.fxLayer.removeChildren()
    const cs = this.cellSize

    this.explosions = this.explosions.filter(exp => {
      exp.age++
      return exp.age < exp.maxAge
    })

    const g = new Graphics()
    this.explosions.forEach(exp => {
      const t       = exp.age / exp.maxAge           // 0 → 1
      const alpha   = Math.max(0, 1 - t * 1.2)
      const radius  = (cs * 0.5) + (cs * 0.9 * t)   // expands outward
      const cx      = exp.x * cs + cs / 2
      const cy      = exp.y * cs + cs / 2

      // Outer ring — palette shifts from yellow to red as age increases
      const colorIdx = Math.min(EXP_COLORS.length - 1, Math.floor(t * EXP_COLORS.length))
      g.circle(cx, cy, radius)
      g.fill({ color: EXP_COLORS[colorIdx], alpha: alpha * 0.85 })

      // Bright core
      g.circle(cx, cy, radius * 0.45)
      g.fill({ color: 0xffffff, alpha: alpha * 0.6 })
    })

    this.fxLayer.addChild(g)
  }

  // ── Countdown overlay ────────────────────────────────────────────────────

  showCountdown(count) {
    const overlay = document.getElementById("battle-city-countdown")
    const countEl = document.getElementById("battle-city-count")
    if (!overlay || !countEl) return

    if (count > 0) {
      overlay.classList.remove("hidden")
      countEl.textContent = count
    } else {
      countEl.textContent = "GO!"
      setTimeout(() => overlay.classList.add("hidden"), 700)
    }
  }

  // ── Game Over overlay ────────────────────────────────────────────────────

  showGameOver(data) {
    const overlay   = document.getElementById("battle-city-game-over")
    const reasonEl  = document.getElementById("battle-city-over-reason")
    const rankEl    = document.getElementById("battle-city-rankings")
    const playAgain = document.getElementById("battle-city-play-again")
    if (!overlay) return

    const reasons = {
      base_destroyed:     "The base was destroyed!",
      last_tank_standing: "Last tank standing!",
      kills_limit:        "Kill limit reached!"
    }
    if (reasonEl) reasonEl.textContent = reasons[data.reason] ?? data.reason ?? ""

    if (rankEl && this.state?.tanks) {
      const COLORS = { yellow: "#f1c40f", green: "#2ecc71", white: "#ecf0f1", red: "#e74c3c" }
      const scores = data.scores ?? {}
      const sorted = Object.entries(scores).sort(([, a], [, b]) => b - a)

      rankEl.innerHTML = sorted.map(([pid, score], idx) => {
        const tank     = this.state.tanks[pid]
        const name     = tank?.nickname ?? `Player ${idx + 1}`
        const color    = COLORS[tank?.color] ?? "#ffffff"
        const medal    = ["🥇", "🥈", "🥉"][idx] ?? `${idx + 1}.`
        const isWinner = pid === data.winner_id || (idx === 0 && data.reason === "kills_limit")
        return `
          <div class="flex items-center justify-between py-1 px-2 rounded-lg ${isWinner ? "bg-yellow-400/10" : ""}">
            <span class="text-slate-400 w-6 text-sm">${medal}</span>
            <span class="flex-1 font-bold text-sm" style="color:${color}">${name}</span>
            <span class="font-mono font-black text-lg" style="color:${color}">${score}</span>
          </div>`
      }).join("")
    }

    if (playAgain && !playAgain._wired) {
      playAgain._wired = true
      playAgain.addEventListener("click", () => {
        this.channel?.perform("restart_game", { room_code: this.roomCodeValue })
      })
    }

    overlay.classList.remove("hidden")
  }

  // ── Rendering ────────────────────────────────────────────────────────────

  get cellSize() {
    return Math.floor(520 / (this.state?.map_cols || 26))
  }

  render() {
    if (!this.state || !this.pixiReady) return
    this.gameLayer.removeChildren()
    this.renderWalls()
    this.renderBase()
    this.renderTanks()
    this.renderBullets()
  }

  renderWalls() {
    const g  = new Graphics()
    const cs = this.cellSize

    Object.entries(this.state.walls).forEach(([key, type]) => {
      const [x, y] = key.split(",").map(Number)
      const ox = x * cs
      const oy = y * cs

      if (type === "brick") {
        this.renderBrick(g, ox, oy, cs)
      } else if (type === "steel") {
        this.renderSteel(g, ox, oy, cs)
      } else {
        g.rect(ox, oy, cs, cs)
        g.fill(WALL_COLORS[type] ?? 0x888888)
      }
    })

    this.gameLayer.addChild(g)
  }

  renderBrick(g, ox, oy, cs) {
    // Background
    g.rect(ox, oy, cs, cs)
    g.fill(0xc0392b)

    // Mortar lines — two rows of staggered bricks
    const hw = Math.floor(cs / 2)
    const hh = Math.ceil(cs / 2)
    const mc = 0x922b21  // mortar color (darker red)

    // Horizontal mortar line between rows
    g.rect(ox, oy + hh - 1, cs, 1)
    g.fill(mc)

    // Vertical mortar row 1 (centered)
    g.rect(ox + hw, oy, 1, hh - 1)
    g.fill(mc)

    // Vertical mortar row 2 (offset by half-brick)
    const offset = Math.floor(hw / 2)
    g.rect(ox + offset, oy + hh, 1, cs - hh)
    g.fill(mc)
    if (ox + offset + hw < ox + cs) {
      g.rect(ox + offset + hw, oy + hh, 1, cs - hh)
      g.fill(mc)
    }
  }

  renderSteel(g, ox, oy, cs) {
    g.rect(ox, oy, cs, cs)
    g.fill(0x7f8c8d)

    // Highlight — top-left bevel
    const bv = Math.max(1, Math.floor(cs * 0.15))
    g.rect(ox, oy, cs, bv)
    g.fill(0xaab7b8)
    g.rect(ox, oy, bv, cs)
    g.fill(0xaab7b8)

    // Shadow — bottom-right bevel
    g.rect(ox, oy + cs - bv, cs, bv)
    g.fill(0x566573)
    g.rect(ox + cs - bv, oy, bv, cs)
    g.fill(0x566573)
  }

  renderBase() {
    const base = this.state.base
    if (!base) return

    const cs = this.cellSize
    const g  = new Graphics()
    const ox = base.x * cs
    const oy = base.y * cs

    if (base.alive) {
      // Eagle silhouette — simplified with a few rectangles
      g.rect(ox, oy, cs, cs).fill(0x1a1a1a)                    // dark background

      // Wings (two side triangles approximated as rects)
      const ww = Math.floor(cs * 0.28)
      const wh = Math.floor(cs * 0.55)
      g.rect(ox + 1,        oy + Math.floor(cs * 0.2), ww, wh).fill(0xf39c12)
      g.rect(ox + cs - ww - 1, oy + Math.floor(cs * 0.2), ww, wh).fill(0xf39c12)

      // Body
      const bw = Math.floor(cs * 0.35)
      const bh = Math.floor(cs * 0.65)
      g.rect(ox + Math.floor((cs - bw) / 2), oy + Math.floor(cs * 0.15), bw, bh).fill(0xf39c12)

      // Head (small square on top)
      const hw = Math.floor(cs * 0.2)
      g.rect(ox + Math.floor((cs - hw) / 2), oy + Math.floor(cs * 0.05), hw, Math.floor(cs * 0.2)).fill(0xf1c40f)
    } else {
      // Destroyed base — dark rubble look
      g.rect(ox, oy, cs, cs).fill(0x2c2c2c)
      const rs = Math.floor(cs * 0.25)
      g.rect(ox + 1,      oy + 1,      rs, rs).fill(0x4a4a4a)
      g.rect(ox + cs - rs - 1, oy + cs - rs - 1, rs, rs).fill(0x3a3a3a)
      g.rect(ox + Math.floor(cs / 2) - 1, oy + Math.floor(cs / 2) - 1, 3, 3).fill(0x555555)
    }

    this.gameLayer.addChild(g)
  }

  renderTanks() {
    const cs = this.cellSize

    Object.entries(this.state.tanks).forEach(([, tank]) => {
      if (!tank.alive) return
      this.renderTankSprite(tank, cs)
    })
  }

  renderTankSprite(tank, cs) {
    const p   = 1                               // outer padding
    const ox  = tank.x * cs + p
    const oy  = tank.y * cs + p
    const sw  = cs - p * 2                      // sprite width
    const sh  = cs - p * 2                      // sprite height
    const col = TANK_COLORS[tank.color] ?? 0xffffff
    const dk  = darkenColor(col)                // track color

    const g  = new Graphics()
    const tw = Math.max(2, Math.floor(sw * 0.22))  // track width

    // ── Tracks ────────────────────────────────────────────────
    g.rect(ox,             oy, tw, sh).fill(dk)
    g.rect(ox + sw - tw,   oy, tw, sh).fill(dk)

    // Tread ridges (lighter horizontal marks)
    const ridges  = 4
    const ridgeH  = 1
    const ridgeC  = darkenColor(col, 0.75)
    for (let i = 1; i < ridges; i++) {
      const ry = oy + Math.floor(sh / ridges * i)
      g.rect(ox,           ry, tw, ridgeH).fill(ridgeC)
      g.rect(ox + sw - tw, ry, tw, ridgeH).fill(ridgeC)
    }

    // ── Body ──────────────────────────────────────────────────
    const bodyX = ox + tw + 1
    const bodyW = sw - (tw + 1) * 2
    g.rect(bodyX, oy + 1, bodyW, sh - 2).fill(col)

    // ── Turret ────────────────────────────────────────────────
    const turW = Math.max(3, Math.floor(sw * 0.3))
    const turH = Math.max(3, Math.floor(sh * 0.3))
    const turX = ox + Math.floor((sw - turW) / 2)
    const turY = oy + Math.floor((sh - turH) / 2)
    g.rect(turX, turY, turW, turH).fill(dk)

    // ── Barrel ────────────────────────────────────────────────
    const barW   = Math.max(2, Math.floor(sw * 0.15))
    const barLen = Math.floor(sw * 0.4)
    const bcx    = ox + Math.floor((sw - barW) / 2)
    const bcy    = oy + Math.floor((sh - barW) / 2)

    switch (tank.direction) {
      case "up":    g.rect(bcx, oy,                barW, barLen).fill(dk); break
      case "down":  g.rect(bcx, oy + sh - barLen,  barW, barLen).fill(dk); break
      case "left":  g.rect(ox,           bcy, barLen, barW).fill(dk); break
      case "right": g.rect(ox + sw - barLen, bcy, barLen, barW).fill(dk); break
    }

    this.gameLayer.addChild(g)
  }

  renderBullets() {
    if (!this.state.bullets?.length) return

    const g    = new Graphics()
    const cs   = this.cellSize
    const size = Math.max(3, Math.floor(cs * 0.22))

    this.state.bullets.forEach(bullet => {
      const offset = Math.floor((cs - size) / 2)
      const bx     = bullet.x * cs + offset
      const by     = bullet.y * cs + offset

      // Glow ring
      g.rect(bx - 1, by - 1, size + 2, size + 2).fill({ color: 0xffd700, alpha: 0.4 })
      // Core
      g.rect(bx, by, size, size).fill(BULLET_COLOR)
    })

    this.gameLayer.addChild(g)
  }
}
