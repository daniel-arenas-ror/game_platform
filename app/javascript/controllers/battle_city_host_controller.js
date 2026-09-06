import { Controller } from "@hotwired/stimulus"
import consumer from "channels/consumer"
import { Application, Graphics } from "pixi.js"

// Colours used for wall types (coloured rectangles — replaced by sprites in Phase 7)
const WALL_COLORS  = { brick: 0xc0392b, steel: 0x7f8c8d, water: 0x2471a3, trees: 0x1e8449 }
const TANK_COLORS  = { yellow: 0xf1c40f, green: 0x2ecc71, white: 0xecf0f1, red: 0xe74c3c }
const BASE_COLOR   = { alive: 0xf39c12, dead: 0x555555 }
const BULLET_COLOR = 0xffffff
const BG_COLOR     = 0x0d0d1a

export default class extends Controller {
  static values = { roomCode: String }

  async connect() {
    this.state   = null
    this.pixiReady = false

    // Boot PixiJS — async in v8
    this.app = new Application()
    await this.app.init({
      width: 520,
      height: 520,
      background: BG_COLOR,
      antialias: false
    })

    // Attach canvas to the host container div
    this.element.appendChild(this.app.canvas)
    this.pixiReady = true

    // Render pending state if a snapshot arrived before PixiJS was ready
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
      connected: () => console.log("[BattleCity] host connected"),
      received:  (data) => this.handleMessage(data)
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

      case "game_over":
        this.showGameOver(data)
        break
    }
  }

  applyDelta(delta) {
    if (!this.state) return
    if (delta.tanks)           Object.assign(this.state.tanks, delta.tanks)
    if (delta.bullets)         this.state.bullets = delta.bullets
    if (delta.walls_destroyed) delta.walls_destroyed.forEach(k => delete this.state.walls[k])
    if (delta.scores)          Object.assign(this.state.scores, delta.scores)
    if (this.pixiReady) this.render()
  }

  // ── Rendering ────────────────────────────────────────────────────────────

  get cellSize() {
    const cols = this.state?.map_cols || 26
    return Math.floor(520 / cols)
  }

  render() {
    if (!this.state || !this.pixiReady) return

    this.app.stage.removeChildren()
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
      g.rect(x * cs, y * cs, cs, cs)
      g.fill(WALL_COLORS[type] ?? 0x888888)
    })

    this.app.stage.addChild(g)
  }

  renderBase() {
    const base = this.state.base
    if (!base) return

    const cs    = this.cellSize
    const color = base.alive ? BASE_COLOR.alive : BASE_COLOR.dead
    const g     = new Graphics()

    g.rect(base.x * cs, base.y * cs, cs, cs)
    g.fill(color)
    this.app.stage.addChild(g)
  }

  renderTanks() {
    const cs      = this.cellSize
    const padding = 2

    Object.values(this.state.tanks).forEach(tank => {
      if (!tank.alive) return

      const g     = new Graphics()
      const color = TANK_COLORS[tank.color] ?? 0xffffff

      g.rect(
        tank.x * cs + padding,
        tank.y * cs + padding,
        cs - padding * 2,
        cs - padding * 2
      )
      g.fill(color)

      // Simple direction indicator — small triangle / notch
      this.addDirectionIndicator(g, tank, cs, padding, color)

      this.app.stage.addChild(g)
    })
  }

  addDirectionIndicator(g, tank, cs, padding, color) {
    // Draw a small dark square on the leading edge to show facing direction
    const notch = Math.max(2, Math.floor(cs / 5))
    const cx    = tank.x * cs + padding + Math.floor((cs - padding * 2) / 2) - Math.floor(notch / 2)
    const cy    = tank.y * cs + padding + Math.floor((cs - padding * 2) / 2) - Math.floor(notch / 2)
    const inner = new Graphics()
    inner.rect(cx, cy, notch, notch)
    inner.fill(0x000000)
    this.app.stage.addChild(inner)
  }

  renderBullets() {
    if (!this.state.bullets?.length) return

    const g    = new Graphics()
    const cs   = this.cellSize
    const size = Math.max(3, Math.floor(cs / 4))

    this.state.bullets.forEach(bullet => {
      const offset = Math.floor((cs - size) / 2)
      g.rect(bullet.x * cs + offset, bullet.y * cs + offset, size, size)
      g.fill(BULLET_COLOR)
    })

    this.app.stage.addChild(g)
  }

  showGameOver(data) {
    // Will be fleshed out in Phase 6 — log for now
    console.log("[BattleCity] game over", data)
  }
}
