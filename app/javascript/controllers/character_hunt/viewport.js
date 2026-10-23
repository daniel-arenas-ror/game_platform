// Pinch-zoom and drag for a canvas that shows a scene (see scene.js). One finger drags, two pinch,
// a mouse wheel zooms, and a short tap that didn't move calls onTap with the spot in the scene
// (fractions of its width and height). The page itself never zooms: the canvas needs
// `touch-action: none`.

const TAP_MOVE = 10  // css px a finger may slide and still tap
const TAP_TIME = 400 // ms

export class Viewport {
  constructor(canvas, { ratio, draw, onTap = () => {}, maxZoom = 8, background = "#0f172a" }) {
    Object.assign(this, { canvas, ratio, draw, onTap, maxZoom, background })
    this.ctx      = canvas.getContext("2d")
    this.pointers = new Map()
    this.zoom     = 1 // 1 = the whole scene fits
    this.ox = this.oy = 0

    this.listeners = {
      pointerdown:   e => this.down(e),
      pointermove:   e => this.move(e),
      pointerup:     e => this.up(e),
      pointercancel: e => this.pointers.delete(e.pointerId),
      wheel:         e => this.wheel(e)
    }
    Object.entries(this.listeners).forEach(([ name, fn ]) => canvas.addEventListener(name, fn, { passive: false }))
    this.observer = new ResizeObserver(() => this.resize())
    this.observer.observe(canvas)
    this.resize()
  }

  destroy() {
    Object.entries(this.listeners).forEach(([ name, fn ]) => this.canvas.removeEventListener(name, fn))
    this.observer.disconnect()
    cancelAnimationFrame(this.frame)
  }

  // Pixels per scene unit (1 unit = the scene's height).
  get scale() { return this.fitScale * this.zoom }

  resize() {
    const rect = this.canvas.getBoundingClientRect()
    const dpr  = window.devicePixelRatio || 1
    const keep = this.width && this.toScene(this.width / 2, this.height / 2)
    this.width  = rect.width
    this.height = rect.height
    this.canvas.width  = Math.max(Math.round(rect.width * dpr), 1)
    this.canvas.height = Math.max(Math.round(rect.height * dpr), 1)
    this.fitScale = Math.min(rect.width / this.ratio, rect.height)
    if (keep) this.centerOn(keep[0], keep[1])
    else this.reset()
    this.paint() // resizing cleared the canvas: draw now, not on the next frame
  }

  // Back to the whole scene.
  reset() {
    this.zoom = 1
    this.centerOn(this.ratio / 2, 0.5)
    this.render()
  }

  // Zooms by `factor` around a point on the canvas (css px; the middle by default).
  zoomBy(factor, px = this.width / 2, py = this.height / 2) {
    const [ sx, sy ] = this.toScene(px, py)
    this.zoom = Math.min(Math.max(this.zoom * factor, 1), this.maxZoom)
    this.ox = px - sx * this.scale
    this.oy = py - sy * this.scale
    this.clamp()
    this.render()
  }

  // Glides to x, y (fractions of the scene) at `zoom`, e.g. to show where the target was.
  focus(x, y, zoom, duration = 900) {
    const from  = { zoom: this.zoom, center: this.toScene(this.width / 2, this.height / 2) }
    const to    = [ x * this.ratio, y ]
    const start = performance.now()
    const step  = now => {
      const k = Math.min((now - start) / duration, 1)
      const e = 1 - Math.pow(1 - k, 3)
      this.zoom = from.zoom + (Math.min(zoom, this.maxZoom) - from.zoom) * e
      this.centerOn(from.center[0] + (to[0] - from.center[0]) * e, from.center[1] + (to[1] - from.center[1]) * e)
      this.paint()
      if (k < 1) this.frame = requestAnimationFrame(step)
    }
    cancelAnimationFrame(this.frame)
    this.frame = requestAnimationFrame(step)
  }

  // Redraws on the next frame (several calls in one frame draw once).
  render() {
    if (this.pending) return
    this.pending = true
    requestAnimationFrame(() => { this.pending = false; this.paint() })
  }

  paint() {
    const dpr = this.canvas.width / this.width
    const ctx = this.ctx
    ctx.setTransform(1, 0, 0, 1, 0, 0)
    ctx.fillStyle = this.background
    ctx.fillRect(0, 0, this.canvas.width, this.canvas.height)
    ctx.setTransform(dpr * this.scale, 0, 0, dpr * this.scale, dpr * this.ox, dpr * this.oy)
    ctx.save()
    ctx.beginPath()
    ctx.rect(0, 0, this.ratio, 1)
    ctx.clip()
    this.draw(ctx)
    ctx.restore()
  }

  // ── Coordinates ──────────────────────────────────────────────────────────

  toScene(px, py) {
    return [ (px - this.ox) / this.scale, (py - this.oy) / this.scale ]
  }

  centerOn(sx, sy) {
    this.ox = this.width / 2 - sx * this.scale
    this.oy = this.height / 2 - sy * this.scale
    this.clamp()
  }

  // The scene always fills the canvas when it's bigger than it, and sits in the middle when smaller.
  clamp() {
    const w = this.ratio * this.scale, h = this.scale
    this.ox = w <= this.width ? (this.width - w) / 2 : Math.min(0, Math.max(this.width - w, this.ox))
    this.oy = h <= this.height ? (this.height - h) / 2 : Math.min(0, Math.max(this.height - h, this.oy))
  }

  point(e) {
    const rect = this.canvas.getBoundingClientRect()
    return [ e.clientX - rect.left, e.clientY - rect.top ]
  }

  // ── Gestures ─────────────────────────────────────────────────────────────

  down(e) {
    e.preventDefault()
    this.canvas.setPointerCapture?.(e.pointerId)
    this.pointers.set(e.pointerId, this.point(e))
    if (this.pointers.size === 1) {
      this.gesture = { start: this.point(e), at: performance.now(), moved: false, pinched: false }
    } else {
      this.gesture.pinched = true
    }
    cancelAnimationFrame(this.frame)
  }

  move(e) {
    if (!this.pointers.has(e.pointerId)) return
    e.preventDefault()
    const before = [ ...this.pointers.values() ]
    this.pointers.set(e.pointerId, this.point(e))
    const after = [ ...this.pointers.values() ]

    if (after.length === 1) {
      const [ [ x0, y0 ] ] = before, [ [ x1, y1 ] ] = after
      const [ sx, sy ] = this.gesture.start
      if (Math.hypot(x1 - sx, y1 - sy) > TAP_MOVE) this.gesture.moved = true
      if (!this.gesture.moved) return
      this.ox += x1 - x0
      this.oy += y1 - y0
      this.clamp()
      this.render()
    } else if (after.length >= 2) {
      const [ a0, b0 ] = before, [ a1, b1 ] = after
      const mid0 = [ (a0[0] + b0[0]) / 2, (a0[1] + b0[1]) / 2 ]
      const mid1 = [ (a1[0] + b1[0]) / 2, (a1[1] + b1[1]) / 2 ]
      const dist0 = Math.hypot(a0[0] - b0[0], a0[1] - b0[1]) || 1
      const dist1 = Math.hypot(a1[0] - b1[0], a1[1] - b1[1])
      this.ox += mid1[0] - mid0[0]
      this.oy += mid1[1] - mid0[1]
      this.zoomBy(dist1 / dist0, mid1[0], mid1[1])
    }
  }

  up(e) {
    if (!this.pointers.has(e.pointerId)) return
    this.pointers.delete(e.pointerId)
    const g = this.gesture
    if (this.pointers.size > 0 || !g) return

    this.gesture = null
    if (g.moved || g.pinched || performance.now() - g.at > TAP_TIME) return
    const [ sx, sy ] = this.toScene(...this.point(e))
    if (sx < 0 || sy < 0 || sx > this.ratio || sy > 1) return
    this.onTap(sx / this.ratio, sy, this.point(e))
  }

  wheel(e) {
    e.preventDefault()
    this.zoomBy(Math.exp(-e.deltaY * 0.0015), ...this.point(e))
  }
}
