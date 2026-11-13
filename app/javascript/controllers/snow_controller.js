import { Controller } from "@hotwired/stimulus"

const FLAKES_PER_PX = 1 / 20  // flakes per pixel of screen width: about 20 on a phone, 70 on a laptop
const MAX_FLAKES    = 90

// Christmas mode: light snow falling over the public pages (layouts/application, only with the
// site header, so never during a game). Nothing for people who ask for less motion, and it stops
// while the tab is hidden. The canvas never takes clicks.
export default class extends Controller {
  connect() {
    if (window.matchMedia("(prefers-reduced-motion: reduce)").matches) return

    this.canvas = document.createElement("canvas")
    this.canvas.setAttribute("aria-hidden", "true")
    this.canvas.className = "pointer-events-none fixed inset-0 z-30 h-full w-full"
    this.element.append(this.canvas)
    this.ctx = this.canvas.getContext("2d")

    this.onResize  = () => this.resize()
    this.onVisible = () => (document.hidden ? this.stop() : this.start())
    window.addEventListener("resize", this.onResize)
    document.addEventListener("visibilitychange", this.onVisible)

    this.resize()
    this.flakes = Array.from({ length: this.count() }, () => this.flake(true))
    this.start()
  }

  disconnect() {
    this.stop()
    window.removeEventListener("resize", this.onResize)
    document.removeEventListener("visibilitychange", this.onVisible)
    this.canvas?.remove()
  }

  count() {
    return Math.min(MAX_FLAKES, Math.round(window.innerWidth * FLAKES_PER_PX))
  }

  resize() {
    const ratio = window.devicePixelRatio || 1
    this.width  = window.innerWidth
    this.height = window.innerHeight
    this.canvas.width  = this.width * ratio
    this.canvas.height = this.height * ratio
    this.ctx.setTransform(ratio, 0, 0, ratio, 0, 0)
  }

  // A new flake: anywhere on screen at the start, then from just above the top.
  flake(anywhere = false) {
    const r = 1 + Math.random() * 2.5
    return {
      x: Math.random() * this.width,
      y: anywhere ? Math.random() * this.height : -r * 2,
      r,
      speed: 0.3 + r * 0.25,               // bigger flakes are closer, so they fall faster
      sway: Math.random() * Math.PI * 2,
      alpha: 0.35 + Math.random() * 0.45
    }
  }

  start() {
    if (this.frame || !this.canvas) return
    const step = () => { this.draw(); this.frame = requestAnimationFrame(step) }
    this.frame = requestAnimationFrame(step)
  }

  stop() {
    cancelAnimationFrame(this.frame)
    this.frame = null
  }

  draw() {
    const { ctx } = this
    ctx.clearRect(0, 0, this.width, this.height)
    this.flakes.forEach((f, i) => {
      f.sway += 0.01
      f.y += f.speed
      f.x += Math.sin(f.sway) * 0.4
      if (f.y > this.height + f.r) this.flakes[i] = f = this.flake()

      ctx.globalAlpha = f.alpha
      ctx.fillStyle = "#fff"
      ctx.beginPath()
      ctx.arc(f.x, f.y, f.r, 0, Math.PI * 2)
      ctx.fill()
    })
  }
}
