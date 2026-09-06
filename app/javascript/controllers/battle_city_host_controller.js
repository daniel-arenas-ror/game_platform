import { Controller } from "@hotwired/stimulus"
import consumer from "channels/consumer"
import { Application, Graphics } from "pixi.js"

const WALL_COLORS  = { brick: 0xc0392b, steel: 0x7f8c8d, water: 0x2471a3, trees: 0x1e8449 }
const TANK_COLORS  = { yellow: 0xf1c40f, green: 0x2ecc71, white: 0xecf0f1, red: 0xe74c3c }
const BASE_COLOR   = { alive: 0xf39c12, dead: 0x555555 }
const BULLET_COLOR = 0xffffff
const BG_COLOR     = 0x0d0d1a

export default class extends Controller {
  static values = { roomCode: String }

  async connect() {
    this.state     = null
    this.pixiReady = false

    this.app = new Application()
    await this.app.init({
      width:      520,
      height:     520,
      background: BG_COLOR,
      antialias:  false
    })

    this.element.appendChild(this.app.canvas)
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
    if (delta.tanks)           Object.assign(this.state.tanks, delta.tanks)
    if (delta.bullets)         this.state.bullets = delta.bullets
    if (delta.walls_destroyed) delta.walls_destroyed.forEach(k => delete this.state.walls[k])
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

  // ── Countdown overlay ────────────────────────────────────────────────────

  showCountdown(count) {
    const overlay  = document.getElementById("battle-city-countdown")
    const countEl  = document.getElementById("battle-city-count")
    if (!overlay || !countEl) return

    if (count > 0) {
      overlay.classList.remove("hidden")
      countEl.textContent = count
    } else {
      countEl.textContent = "GO!"
      setTimeout(() => overlay.classList.add("hidden"), 700)
    }
  }

  // ── Rendering ────────────────────────────────────────────────────────────

  get cellSize() {
    return Math.floor(520 / (this.state?.map_cols || 26))
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

    Object.entries(this.state.tanks).forEach(([playerId, tank]) => {
      if (!tank.alive) return

      const color = TANK_COLORS[tank.color] ?? 0xffffff
      const bx    = tank.x * cs + padding
      const by    = tank.y * cs + padding
      const bw    = cs - padding * 2
      const bh    = cs - padding * 2

      // Tank body
      const g = new Graphics()
      g.rect(bx, by, bw, bh)
      g.fill(color)
      this.app.stage.addChild(g)

      // Direction indicator — thin dark bar on the leading edge
      this.renderBarrel(tank, cs, padding, color)
    })
  }

  renderBarrel(tank, cs, padding, color) {
    const barW  = Math.max(2, Math.floor(cs / 4))
    const barH  = Math.max(2, Math.floor(cs / 4))
    const halfW = Math.floor((cs - padding * 2) / 2) - Math.floor(barW / 2)
    const halfH = Math.floor((cs - padding * 2) / 2) - Math.floor(barH / 2)
    const ox    = tank.x * cs + padding
    const oy    = tank.y * cs + padding
    const size  = cs - padding * 2

    let bx, by
    switch (tank.direction) {
      case "up":    bx = ox + halfW;        by = oy;                break
      case "down":  bx = ox + halfW;        by = oy + size - barH;  break
      case "left":  bx = ox;                by = oy + halfH;        break
      case "right": bx = ox + size - barW;  by = oy + halfH;        break
      default:      return
    }

    const barrel = new Graphics()
    barrel.rect(bx, by, barW, barH)
    barrel.fill(0x000000)
    this.app.stage.addChild(barrel)
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
    const overlay   = document.getElementById("battle-city-game-over")
    const reasonEl  = document.getElementById("battle-city-over-reason")
    const rankEl    = document.getElementById("battle-city-rankings")
    const playAgain = document.getElementById("battle-city-play-again")
    if (!overlay) return

    // Reason text
    const reasons = {
      base_destroyed:      "The base was destroyed!",
      last_tank_standing:  "Last tank standing!",
      kills_limit:         "Kill limit reached!"
    }
    if (reasonEl) reasonEl.textContent = reasons[data.reason] ?? data.reason ?? ""

    // Ranked list
    if (rankEl && this.state?.tanks) {
      const COLORS = { yellow: "#f1c40f", green: "#2ecc71", white: "#ecf0f1", red: "#e74c3c" }
      const scores = data.scores ?? {}
      const sorted = Object.entries(scores)
        .sort(([, a], [, b]) => b - a)

      rankEl.innerHTML = sorted.map(([pid, score], idx) => {
        const tank    = this.state.tanks[pid]
        const name    = tank?.nickname ?? `Player ${idx + 1}`
        const color   = COLORS[tank?.color] ?? "#ffffff"
        const medal   = ["🥇", "🥈", "🥉"][idx] ?? `${idx + 1}.`
        const isWinner = pid === data.winner_id || (idx === 0 && data.reason === "kills_limit")
        return `
          <div class="flex items-center justify-between py-1 px-2 rounded-lg ${isWinner ? "bg-yellow-400/10" : ""}">
            <span class="text-slate-400 w-6 text-sm">${medal}</span>
            <span class="flex-1 font-bold text-sm" style="color: ${color}">${name}</span>
            <span class="font-mono font-black text-lg" style="color: ${color}">${score}</span>
          </div>`
      }).join("")
    }

    // Wire Play Again button (once)
    if (playAgain && !playAgain._wired) {
      playAgain._wired = true
      playAgain.addEventListener("click", () => {
        this.channel?.perform("restart_game", { room_code: this.roomCodeValue })
      })
    }

    overlay.classList.remove("hidden")
  }
}

