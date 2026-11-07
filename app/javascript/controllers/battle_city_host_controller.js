import { Controller } from "@hotwired/stimulus"
import consumer from "channels/consumer"
import { t } from "controllers/shared/i18n"
import { escapeHtml } from "controllers/shared/html"
import { avatarHtml } from "controllers/shared/avatar"
import { Application, Graphics, Container } from "pixi.js"
import { soundFile } from "controllers/shared/sound"

const WALL_COLORS  = { brick: 0xc0392b, steel: 0x7f8c8d, water: 0x2471a3, trees: 0x1e8449 }
const TANK_COLORS  = { yellow: 0xf1c40f, green: 0x2ecc71, white: 0xecf0f1, red: 0xe74c3c,
                       blue: 0x3498db, purple: 0x9b59b6, orange: 0xe67e22, pink: 0xff79c6, silver: 0x95a5a6 }
const BULLET_COLOR = 0xffffff
const BG_COLOR     = 0x0d0d1a

// Christmas maps (map_theme "christmas"): night-blue snow ground, twinkling bulbs, falling snow.
const CHRISTMAS_BG = 0x0b1730
const BULB_COLORS  = [0xff3b3b, 0x2ecc71, 0xffd23f, 0x3fa9ff]
const TWINKLE_MS   = 450
const SNOWFLAKES   = 70

// Explosion palette: yellow → orange → red as age increases
const EXP_COLORS = [0xffd700, 0xffa500, 0xff6600, 0xcc3300]

// The server works on a grid: a tank moves one cell every 4 ticks (240 ms), a bullet one cell
// every tick (60 ms). The TV slides between cells over a little longer than that, so a tank
// driving straight never stops between cells even when an update arrives a bit late.
const MOVE_MS     = 250
const BULLET_MS   = 64
const TURN_MS     = 90
const RECOIL_MS   = 140
const FLASH_MS    = 90
const SPAWN_MS    = 300
const SHIELD_BLINK_MS = 120 // a tank that just came back flickers while bullets can't hurt it
const SHAKE_MS    = 280
const ANGLES      = { up: 0, right: Math.PI / 2, down: Math.PI, left: -Math.PI / 2 }
const DIRS        = { up: [0, -1], down: [0, 1], left: [-1, 0], right: [1, 0] }

function darkenColor(hex, factor = 0.55) {
  const r = Math.round(((hex >> 16) & 0xff) * factor)
  const g = Math.round(((hex >>  8) & 0xff) * factor)
  const b = Math.round(( hex        & 0xff) * factor)
  return (r << 16) | (g << 8) | b
}

const clamp01 = (v) => Math.max(0, Math.min(1, v))
const easeOut = (k) => 1 - (1 - k) * (1 - k)
const mod     = (a, n) => ((a % n) + n) % n

export default class extends Controller {
  static values = { roomCode: String }

  async connect() {
    this.state      = null
    this.pixiReady  = false
    this.explosions = []          // [{x, y, start, duration, color, scale}] in cells / ms
    this.tanks      = new Map()   // id → sprite + its slide/turn animation
    this.bullets    = new Map()   // id → {fromX, fromY, toX, toY, x, y, t0, direction}
    this.shakeAt    = -Infinity
    this.calm       = window.matchMedia?.("(prefers-reduced-motion: reduce)").matches

    const app = new Application()
    this.app  = app
    await app.init({
      width:      520,
      height:     520,
      background: BG_COLOR,
      antialias:  false
    })

    // Disconnected (e.g. page reload) while pixi was starting — drop this instance.
    if (this.app !== app) {
      app.destroy(true)
      return
    }

    this.element.appendChild(this.app.canvas)

    // world (shakes on explosions) → map, light bulbs, tanks, bullets, effects, snow
    this.world       = new Container()
    this.staticLayer = new Graphics()
    this.tankLayer   = new Container()
    this.bulletLayer = new Graphics()
    this.lightsLayer = new Graphics()
    this.fxLayer     = new Graphics()
    this.snowLayer   = new Graphics()
    this.world.addChild(this.staticLayer, this.lightsLayer, this.tankLayer, this.bulletLayer, this.fxLayer, this.snowLayer)
    this.app.stage.addChild(this.world)

    // Every frame: positions come from the animations, not straight from the server cells.
    this.app.ticker.add(() => this.frame(performance.now()))

    this.pixiReady = true
    if (this.state) this.buildScene()

    this.subscribe()
  }

  disconnect() {
    this.winSound?.pause()
    this.channel?.unsubscribe()
    // Before init finishes, destroy() throws; connect() cleans up that instance instead.
    if (this.pixiReady) this.app.destroy(true)
    this.app       = null
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
        this.channel.perform("start_game_loop", { room_code: this.roomCodeValue })
      },
      received: (data) => this.handleMessage(data)
    })
  }

  handleMessage(data) {
    switch (data.action) {
      case "state_snapshot":
        this.state = data.state
        if (this.pixiReady) this.buildScene()
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

      case "game_changed":
        window.location.href = `/rooms/${this.roomCodeValue}`
        break
    }
  }

  applyDelta(delta) {
    if (!this.state) return
    const now = performance.now()

    // Shots kick back the barrel, even a bullet that hit something in the same tick.
    ;(delta.shots || []).forEach(id => { const tank = this.tanks.get(id); if (tank) tank.firedAt = now })

    if (delta.bullets) {
      this.state.bullets = delta.bullets
      if (this.pixiReady) this.syncBullets(delta.bullets, now)
    }

    if (delta.tanks) {
      Object.entries(delta.tanks).forEach(([id, tank]) => {
        if (this.pixiReady) this.updateTank(id, tank, now)
      })
      Object.assign(this.state.tanks, delta.tanks)
    }

    if (delta.walls_destroyed) {
      delta.walls_destroyed.forEach(k => {
        const [x, y] = k.split(",").map(Number)
        this.spawnExplosion(x, y, null, now)   // null color → brick dust
        delete this.state.walls[k]
      })
      if (this.pixiReady) this.renderStatic()
    }

    if (delta.scores) {
      Object.assign(this.state.scores, delta.scores)
      this.updateScoreboard(delta.scores)
    }
  }

  updateScoreboard(scores) {
    Object.entries(scores).forEach(([playerId, score]) => {
      const el = document.getElementById(`score-${playerId}`)
      if (el) el.textContent = score
    })
  }

  // ── Scene ────────────────────────────────────────────────────────────────

  get cellSize() {
    return Math.floor(520 / (this.state?.map_cols || 26))
  }

  // Full rebuild from a snapshot (first load, reconnect). Everything snaps into place.
  buildScene() {
    if (!this.state || !this.pixiReady) return
    this.app.renderer.background.color = this.christmas ? CHRISTMAS_BG : BG_COLOR
    this.renderStatic()

    this.tankLayer.removeChildren().forEach(c => c.destroy({ children: true }))
    this.tanks.clear()
    const now = performance.now()
    Object.entries(this.state.tanks || {}).forEach(([id, tank]) => { this.addTank(id, tank, now).spawnAt = -Infinity })

    this.bullets.clear()
    ;(this.state.bullets || []).forEach(b => this.bullets.set(b.id, {
      fromX: b.x, fromY: b.y, toX: b.x, toY: b.y, x: b.x, y: b.y, t0: -Infinity, direction: b.direction
    }))
  }

  frame(now) {
    if (!this.state || !this.pixiReady) return
    this.tanks.forEach(tank => this.animateTank(tank, now))
    this.drawBullets(now)
    this.drawFX(now)
    this.drawLights(now)
    this.drawSnow(now)
    this.shake(now)
  }

  get christmas() {
    return this.state?.map_theme === "christmas"
  }

  // ── Tanks ────────────────────────────────────────────────────────────────

  // A tank is drawn once, facing up around (0, 0); moving and turning only change its
  // position and rotation. Treads, barrel and muzzle flash are separate so they can animate.
  addTank(id, tank, now) {
    const cs   = this.cellSize
    const sw   = cs - 2
    const h    = sw / 2
    const col  = TANK_COLORS[tank.color] ?? 0xffffff
    const dk   = darkenColor(col)
    const tw   = Math.max(2, Math.floor(sw * 0.22))
    const view = new Container()

    const hull = new Graphics()
    hull.rect(-h, -h, tw, sw).fill(dk)
    hull.rect(h - tw, -h, tw, sw).fill(dk)
    hull.rect(-h + tw + 1, -h + 1, sw - (tw + 1) * 2, sw - 2).fill(col)
    const turW = Math.max(3, Math.floor(sw * 0.3))
    hull.rect(-turW / 2, -turW / 2, turW, turW).fill(dk)
    if (id.startsWith("bot_")) {
      // Bot indicator — small red crosshair on the turret
      hull.rect(-1, -turW / 2, 2, turW).fill(0xe74c3c)
      hull.rect(-turW / 2, -1, turW, 2).fill(0xe74c3c)
    }

    const treads = new Graphics()
    const barW   = Math.max(2, Math.floor(sw * 0.15))
    const barrel = new Graphics().rect(-barW / 2, -h, barW, Math.floor(sw * 0.4)).fill(dk)
    const flash  = new Graphics().circle(0, -h - 1, Math.max(2, cs * 0.18)).fill({ color: 0xffe066 })
    flash.alpha  = 0

    view.addChild(hull, treads, barrel, flash)
    this.tankLayer.addChild(view)

    const sprite = {
      view, treads, barrel, flash, h, tw, sw, ridge: darkenColor(col, 0.75),
      fromX: tank.x, fromY: tank.y, toX: tank.x, toY: tank.y, x: tank.x, y: tank.y, t0: -Infinity,
      fromAngle: ANGLES[tank.direction] ?? 0, toAngle: ANGLES[tank.direction] ?? 0, a0: -Infinity,
      travel: 0, firedAt: -Infinity, spawnAt: now, alive: tank.alive, color: tank.color,
      shielded: !!tank.shield_until
    }
    view.visible = tank.alive
    this.tanks.set(id, sprite)
    this.drawTreads(sprite)
    this.animateTank(sprite, now)
    return sprite
  }

  updateTank(id, tank, now) {
    const sprite = this.tanks.get(id)
    if (!sprite) return this.addTank(id, tank, now)

    if (sprite.alive && !tank.alive) {
      // Killed: the explosion goes where the tank is drawn right now.
      this.spawnExplosion(sprite.x, sprite.y, sprite.color, now)
      this.shakeAt = now
    }

    const respawned = !sprite.alive && tank.alive
    const jump      = Math.abs(tank.x - sprite.x) + Math.abs(tank.y - sprite.y) > 1.5
    if (respawned || jump) {
      Object.assign(sprite, { fromX: tank.x, fromY: tank.y, toX: tank.x, toY: tank.y, t0: -Infinity })
      if (respawned) sprite.spawnAt = now
    } else if (tank.x !== sprite.toX || tank.y !== sprite.toY) {
      // Slide on from wherever it is drawn now, so a late update never makes it jump back.
      Object.assign(sprite, { fromX: sprite.x, fromY: sprite.y, toX: tank.x, toY: tank.y, t0: now })
    }

    const target = ANGLES[tank.direction] ?? 0
    const angle  = sprite.view.rotation
    const diff   = mod(target - angle + Math.PI, Math.PI * 2) - Math.PI   // shortest way round
    if (Math.abs(diff) > 0.001) {
      sprite.fromAngle = respawned ? target : angle
      sprite.toAngle   = angle + diff
      sprite.a0        = respawned ? -Infinity : now
    }

    sprite.alive        = tank.alive
    sprite.shielded     = !!tank.shield_until
    sprite.view.visible = tank.alive
  }

  animateTank(s, now) {
    const k  = clamp01((now - s.t0) / MOVE_MS)
    const x  = s.fromX + (s.toX - s.fromX) * k
    const y  = s.fromY + (s.toY - s.fromY) * k
    const cs = this.cellSize

    const moved = Math.abs(x - s.x) + Math.abs(y - s.y)
    s.x = x
    s.y = y
    s.view.position.set((x + 0.5) * cs, (y + 0.5) * cs)
    if (moved > 0) {
      s.travel += moved * cs
      this.drawTreads(s)
    }

    const a = easeOut(clamp01((now - s.a0) / TURN_MS))
    s.view.rotation = s.fromAngle + (s.toAngle - s.fromAngle) * a

    // Fired: the barrel kicks back and a flash shows at its tip.
    s.barrel.y    = Math.round(2 * (1 - clamp01((now - s.firedAt) / RECOIL_MS)))
    s.flash.alpha = 1 - clamp01((now - s.firedAt) / FLASH_MS)

    // Respawn: fades and grows in.
    const sp = easeOut(clamp01((now - s.spawnAt) / SPAWN_MS))
    const blink = s.shielded && Math.floor(now / SHIELD_BLINK_MS) % 2 === 1
    s.view.alpha = blink ? sp * 0.25 : sp
    s.view.scale.set(0.6 + 0.4 * sp)
  }

  // Tread marks roll along with the distance driven.
  drawTreads(s) {
    const g       = s.treads.clear()
    const spacing = s.sw / 4
    for (let i = 0; i < 4; i++) {
      const y = -s.h + mod(i * spacing - s.travel, s.sw)
      if (y < -s.h + 1) continue
      g.rect(-s.h, y, s.tw, 1).fill(s.ridge)
      g.rect(s.h - s.tw, y, s.tw, 1).fill(s.ridge)
    }
  }

  // ── Bullets ──────────────────────────────────────────────────────────────

  syncBullets(list, now) {
    const seen = new Set()
    list.forEach(b => {
      seen.add(b.id)
      const cur = this.bullets.get(b.id)
      if (cur) {
        if (cur.toX !== b.x || cur.toY !== b.y) {
          Object.assign(cur, { fromX: cur.x, fromY: cur.y, toX: b.x, toY: b.y, t0: now })
        }
        return
      }
      // New shot: it leaves from the tip of the barrel.
      const owner    = this.tanks.get(b.owner_id)
      const [dx, dy] = DIRS[b.direction] ?? [0, 0]
      const sx = owner ? owner.x + dx * 0.5 : b.x - dx
      const sy = owner ? owner.y + dy * 0.5 : b.y - dy
      this.bullets.set(b.id, { fromX: sx, fromY: sy, toX: b.x, toY: b.y, x: sx, y: sy, t0: now, direction: b.direction })
    })

    // Gone: it hit something at the edge of the next cell.
    this.bullets.forEach((b, id) => {
      if (seen.has(id)) return
      const [dx, dy] = DIRS[b.direction] ?? [0, 0]
      this.spawnSpark(b.x + dx * 0.5, b.y + dy * 0.5, now)
      this.bullets.delete(id)
    })
  }

  drawBullets(now) {
    const g    = this.bulletLayer.clear()
    const cs   = this.cellSize
    const size = Math.max(3, Math.floor(cs * 0.22))

    this.bullets.forEach(b => {
      const k = clamp01((now - b.t0) / BULLET_MS)
      b.x = b.fromX + (b.toX - b.fromX) * k
      b.y = b.fromY + (b.toY - b.fromY) * k

      const [dx, dy] = DIRS[b.direction] ?? [0, 0]
      const px = (b.x + 0.5) * cs - size / 2
      const py = (b.y + 0.5) * cs - size / 2

      // Fading streak behind it
      for (let i = 3; i >= 1; i--) {
        g.rect(px - dx * i * size, py - dy * i * size, size, size).fill({ color: 0xffd700, alpha: 0.1 * (4 - i) })
      }
      // Glow ring
      g.rect(px - 1, py - 1, size + 2, size + 2).fill({ color: 0xffd700, alpha: 0.4 })
      // Core
      g.rect(px, py, size, size).fill(BULLET_COLOR)
    })
  }

  // ── Explosions ───────────────────────────────────────────────────────────

  spawnExplosion(x, y, tankColor, now = performance.now()) {
    this.explosions.push({
      x, y, start: now,
      duration: tankColor ? 370 : 170,   // tank kill → longer; brick → short flash
      color:    tankColor ? (TANK_COLORS[tankColor] ?? 0xffffff) : WALL_COLORS.brick,
      scale:    1
    })
  }

  spawnSpark(x, y, now) {
    this.explosions.push({ x, y, start: now, duration: 120, color: 0xffd700, scale: 0.35 })
  }

  drawFX(now) {
    const g  = this.fxLayer.clear()
    const cs = this.cellSize

    this.explosions = this.explosions.filter(exp => now - exp.start < exp.duration)
    this.explosions.forEach(exp => {
      const t      = (now - exp.start) / exp.duration   // 0 → 1
      const alpha  = Math.max(0, 1 - t * 1.2)
      const radius = ((cs * 0.5) + (cs * 0.9 * t)) * exp.scale
      const cx     = (exp.x + 0.5) * cs
      const cy     = (exp.y + 0.5) * cs

      // Outer ring — palette shifts from yellow to red as age increases
      const colorIdx = Math.min(EXP_COLORS.length - 1, Math.floor(t * EXP_COLORS.length))
      g.circle(cx, cy, radius).fill({ color: EXP_COLORS[colorIdx], alpha: alpha * 0.85 })

      // Bright core
      g.circle(cx, cy, radius * 0.45).fill({ color: 0xffffff, alpha: alpha * 0.6 })
    })
  }

  // A short shake of the whole map when a tank blows up.
  shake(now) {
    const k = 1 - clamp01((now - this.shakeAt) / SHAKE_MS)
    if (k <= 0 || this.calm) {
      this.world.position.set(0, 0)
      return
    }
    const amp = 4 * k
    this.world.position.set(Math.round((Math.random() * 2 - 1) * amp), Math.round((Math.random() * 2 - 1) * amp))
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
      countEl.textContent = t("battle_city.go")
      setTimeout(() => overlay.classList.add("hidden"), 700)
    }
  }

  // ── Game Over overlay ────────────────────────────────────────────────────

  showGameOver(data) {
    this.winSound = soundFile("/games/sounds/Triumphant_win.mp3")
    this.winSound.play().catch(() => {}) // ignore autoplay blocks
    const overlay   = document.getElementById("battle-city-game-over")
    const reasonEl  = document.getElementById("battle-city-over-reason")
    const rankEl    = document.getElementById("battle-city-rankings")
    const playAgain = document.getElementById("battle-city-play-again")
    if (!overlay) return

    if (reasonEl) reasonEl.textContent = data.reason ? t(`battle_city.reasons.${data.reason}`) : ""

    if (rankEl && this.state?.tanks) {
      const scores = data.scores ?? {}
      const sorted = Object.entries(scores).sort(([, a], [, b]) => b - a)

      rankEl.innerHTML = sorted.map(([pid, score], idx) => {
        const tank     = this.state.tanks[pid]
        const nickname = tank?.nickname ?? t("battle_city.player", { n: idx + 1 })
        const name     = escapeHtml(nickname)
        const color    = `#${(TANK_COLORS[tank?.color] ?? 0xffffff).toString(16).padStart(6, "0")}`
        const medal    = ["🥇", "🥈", "🥉"][idx] ?? `${idx + 1}.`
        const isWinner = pid === data.winner_id || (idx === 0 && data.reason === "kills_limit")
        return `
          <div class="flex items-center justify-between py-1 px-2 rounded-lg ${isWinner ? "bg-yellow-400/10" : ""}">
            <span class="text-slate-400 w-6 text-sm">${medal}</span>
            ${avatarHtml(nickname, "size-7 mr-2")}
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

  // ── Map: walls + base (redrawn only when a brick breaks) ────────────────

  renderStatic() {
    const g = this.staticLayer.clear()
    this.bulbs     = []    // where the light strings' bulbs go; drawLights colours them
    this.bulbPhase = null
    this.renderWalls(g)
    this.renderBase(g)
  }

  renderWalls(g) {
    const cs = this.cellSize

    Object.entries(this.state.walls).forEach(([key, type]) => {
      const [x, y] = key.split(",").map(Number)
      const ox = x * cs
      const oy = y * cs

      if (type === "brick") {
        this.renderBrick(g, ox, oy, cs)
      } else if (type === "steel") {
        this.renderSteel(g, ox, oy, cs)
      } else if (type === "trees") {
        this.renderTrees(g, ox, oy, cs)
      } else if (type === "pine") {
        this.renderPine(g, ox, oy, cs)
      } else if (type === "reindeer") {
        this.renderReindeer(g, ox, oy, cs, x % 2 === 1)
      } else if (type === "lights") {
        this.renderLights(g, ox, oy, cs)
      } else {
        g.rect(ox, oy, cs, cs)
        g.fill(WALL_COLORS[type] ?? 0x888888)
      }
    })
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

  renderTrees(g, ox, oy, cs) {
    // Dark green base
    g.rect(ox, oy, cs, cs).fill(0x1a5c2a)

    // Two lighter green "canopy" blobs
    const r = Math.max(2, Math.floor(cs * 0.28))
    g.circle(ox + Math.floor(cs * 0.33), oy + Math.floor(cs * 0.38), r)
    g.fill({ color: 0x27ae60, alpha: 0.9 })
    g.circle(ox + Math.floor(cs * 0.67), oy + Math.floor(cs * 0.55), r)
    g.fill({ color: 0x2ecc71, alpha: 0.85 })
  }

  // ── Christmas cells (drawn on a 20-unit grid, scaled to the cell) ─────

  // A decorated tree: two tiers, a trunk, baubles and a star.
  renderPine(g, ox, oy, cs) {
    const u = cs / 20
    const P = (x, y) => [ox + x * u, oy + y * u]
    g.rect(ox + 9 * u, oy + 16 * u, 2 * u, 3 * u).fill(0x6e3b1f)
    g.poly([...P(10, 3), ...P(16, 10), ...P(4, 10)]).fill(0x1e8449)
    g.poly([...P(10, 6), ...P(18, 16.5), ...P(2, 16.5)]).fill(0x196f3d)
    ;[[7, 14, 0xe74c3c], [13, 13, 0xf1c40f], [10, 9.5, 0x3fa9ff], [11.5, 15.5, 0xe74c3c], [8.5, 11.5, 0xf1c40f]]
      .forEach(([x, y, color]) => g.circle(ox + x * u, oy + y * u, 1.1 * u).fill(color))
    g.star(ox + 10 * u, oy + 2.5 * u, 5, 2.4 * u, 1 * u).fill(0xffd23f)
  }

  // A reindeer standing side-on with antlers and a red nose; `flip` faces it left.
  renderReindeer(g, ox, oy, cs, flip) {
    const u = cs / 20
    const R = (x, y, w, h, color) => g.rect(ox + (flip ? 20 - x - w : x) * u, oy + y * u, w * u, h * u).fill(color)
    const fur = 0x9c6233, dark = 0x5d3a1a, antler = 0xe8d5b0
    R(3, 9, 11, 6, fur)                                   // body
    ;[4, 7, 10, 12].forEach(x => R(x, 15, 2, 4, dark))    // legs
    R(12, 6, 3, 4, fur)                                   // neck
    R(13, 4, 5, 4, fur)                                   // head
    R(14, 1, 1, 3, antler); R(12, 1, 3, 1, antler)        // antlers
    R(17, 1, 1, 3, antler); R(17, 1, 3, 1, antler)
    R(2, 9, 2, 2, 0xf5f5f5)                               // tail
    R(15, 5, 1, 1, 0x111111)                              // eye
    g.circle(ox + (flip ? 1 : 19) * u, oy + 6.5 * u, 1.4 * u).fill(0xff2b2b)
  }

  // A snowy fence with a string of bulbs; the bulbs themselves twinkle in drawLights.
  renderLights(g, ox, oy, cs) {
    g.rect(ox, oy, cs, cs).fill(0x1b2f55)
    g.rect(ox, oy, cs, Math.max(1, Math.round(cs * 0.15))).fill(0xe8f1ff)
    const wireY = oy + Math.round(cs * 0.45)
    g.rect(ox, wireY, cs, 1).fill(0x2e7d32)
    this.bulbs.push({ x: ox + cs * 0.25, y: wireY + cs * 0.18 }, { x: ox + cs * 0.75, y: wireY + cs * 0.18 })
  }

  // Each bulb steps through the colours, all redrawn only when the step changes.
  drawLights(now) {
    if (!this.bulbs) return
    const phase = this.calm ? 0 : Math.floor(now / TWINKLE_MS)
    if (phase === this.bulbPhase) return
    this.bulbPhase = phase
    const g = this.lightsLayer.clear()
    const r = this.cellSize * 0.14
    this.bulbs.forEach((bulb, i) => {
      const color = BULB_COLORS[(i + phase) % BULB_COLORS.length]
      g.circle(bulb.x, bulb.y, r * 2.2).fill({ color, alpha: 0.22 })
      g.circle(bulb.x, bulb.y, r).fill(color)
    })
  }

  // Light snow falling over the whole map (still flakes with reduced motion).
  drawSnow(now) {
    const g = this.snowLayer.clear()
    if (!this.christmas) return
    const size = this.cellSize * (this.state.map_cols || 26)
    this.flakes ??= Array.from({ length: SNOWFLAKES }, () => ({
      x: Math.random() * size, y: Math.random() * size,
      speed: 12 + Math.random() * 22, radius: 0.8 + Math.random() * 1.6, drift: Math.random() * Math.PI * 2
    }))
    const t = this.calm ? 0 : now / 1000
    this.flakes.forEach(f => {
      const x = mod(f.x + Math.sin(t * 0.8 + f.drift) * 6, size)
      const y = mod(f.y + f.speed * t, size)
      g.circle(x, y, f.radius).fill({ color: 0xffffff, alpha: 0.7 })
    })
  }

  renderBase(g) {
    const base = this.state.base
    if (!base) return

    const cs = this.cellSize
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
  }
}
