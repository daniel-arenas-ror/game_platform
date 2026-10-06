// Shared by the Doodle Dash host (TV) and player (artist's phone) controllers.
//
// Points are fractions of the canvas (0–1), so a drawing made on a phone fits any TV.
// Brush sizes are per 1000 px of canvas width. Both lists must match GameServices::DoodleDash.

export const PALETTE     = [ "#111827", "#ef4444", "#f97316", "#facc15", "#22c55e", "#3b82f6", "#a855f7", "#92400e", "#ffffff" ]
export const ERASER      = "#ffffff"
export const BRUSH_SIZES = [ 4, 10, 24 ]
export const ASPECT      = 4 / 3 // canvas width / height, the same on every screen
export const PAPER       = "#ffffff"

export const MEDALS = { 1: "🥇", 2: "🥈", 3: "🥉" }

// Sizes the canvas buffer to its on-screen size (sharp on retina screens) and clears it.
export function fitCanvas(canvas) {
  const ratio = window.devicePixelRatio || 1
  const rect  = canvas.getBoundingClientRect()
  canvas.width  = Math.max(Math.round(rect.width * ratio), 1)
  canvas.height = Math.max(Math.round(rect.height * ratio), 1)
  clearCanvas(canvas)
}

export function clearCanvas(canvas) {
  const ctx = canvas.getContext("2d")
  ctx.fillStyle = PAPER
  ctx.fillRect(0, 0, canvas.width, canvas.height)
}

// A pen draws one stroke as smooth curves: each piece is a quadratic curve between the midpoints of
// two moves, bent through the point between them. Points can arrive in batches (live, from the
// phone); call end() when the stroke is finished to draw its last half-piece.
export function createPen(canvas, color, size) {
  let last = null // last point added
  let mid  = null // where the previous curve ended

  const setup = () => {
    const ctx = canvas.getContext("2d")
    ctx.strokeStyle = color
    ctx.fillStyle   = color
    ctx.lineWidth   = Math.max(size * canvas.width / 1000, 1)
    ctx.lineCap     = "round"
    ctx.lineJoin    = "round"
    return ctx
  }
  const px = ([ x, y ]) => [ x * canvas.width, y * canvas.height ]

  return {
    add(points) {
      const ctx = setup()
      points.forEach(point => {
        if (!last) {
          // A tap with no movement is a dot.
          const [ x, y ] = px(point)
          ctx.beginPath()
          ctx.arc(x, y, ctx.lineWidth / 2, 0, Math.PI * 2)
          ctx.fill()
          last = mid = point
          return
        }
        const next = [ (last[0] + point[0]) / 2, (last[1] + point[1]) / 2 ]
        ctx.beginPath()
        ctx.moveTo(...px(mid))
        ctx.quadraticCurveTo(...px(last), ...px(next))
        ctx.stroke()
        last = point
        mid  = next
      })
    },
    end() {
      if (!last || last === mid) return
      const ctx = setup()
      ctx.beginPath()
      ctx.moveTo(...px(mid))
      ctx.lineTo(...px(last))
      ctx.stroke()
      mid = last
    }
  }
}

// strokes: [{ color, size, points }]
export function redraw(canvas, strokes) {
  clearCanvas(canvas)
  strokes.forEach(s => {
    const pen = createPen(canvas, s.color, s.size)
    pen.add(s.points)
    pen.end()
  })
}

// "c _ _ " pattern for the word: nil letters are hidden, spaces and punctuation are shown.
// `cascade`: the letters pop in one after another (the reveal).
export function patternHtml(pattern, big = true, cascade = false) {
  if (!pattern) return ""
  const box = big ? "w-[0.9em] border-b-4" : "w-[0.8em] border-b-2"
  return pattern.map((ch, i) => {
    if (ch === " ") return `<span class="inline-block w-[0.6em]"></span>`
    if (ch === null) return `<span class="inline-block ${box} border-current mx-[0.08em] opacity-70">&nbsp;</span>`
    const pop = cascade ? ` dd-pop" style="animation-delay:${i * 70}ms;animation-fill-mode:backwards` : ""
    return `<span class="inline-block ${box} border-transparent mx-[0.08em] text-center${pop}">${esc(ch.toUpperCase())}</span>`
  }).join("")
}

export function ranked(scores) {
  const entries = Object.entries(scores || {}).sort((a, b) => b[1] - a[1])
  return entries.map(([ id, pts ]) => ({ id, pts, place: 1 + entries.filter(([ , p ]) => p > pts).length }))
}

export function esc(str) {
  return String(str).replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;").replace(/"/g, "&quot;")
}

// Seconds left until an epoch timestamp (seconds), never negative.
export function secondsUntil(endsAt) {
  return Math.max(Math.round(endsAt - Date.now() / 1000), 0)
}

export function restartAnimation(el, className) {
  if (!el) return
  el.classList.remove(className)
  void el.offsetWidth
  el.classList.add(className)
}

const STYLE_ID = "doodle-dash-styles"
const STYLES = `
  @keyframes dd-pop   { 0% { transform: scale(0.6); opacity: 0 } 60% { transform: scale(1.12); opacity: 1 } 100% { transform: scale(1) } }
  @keyframes dd-slide { from { transform: translateY(12px); opacity: 0 } to { transform: none; opacity: 1 } }
  @keyframes dd-shake { 0%, 100% { transform: translateX(0) } 20%, 60% { transform: translateX(-8px) } 40%, 80% { transform: translateX(8px) } }
  @keyframes dd-pulse { 0% { transform: scale(1) } 30% { transform: scale(1.18) } 100% { transform: scale(1) } }
  .dd-pop   { animation: dd-pop 0.35s ease-out; }
  .dd-slide { animation: dd-slide 0.3s cubic-bezier(0.22, 1, 0.36, 1); }
  .dd-shake { animation: dd-shake 0.4s ease-in-out; }
  .dd-pulse { animation: dd-pulse 0.5s ease-out; }
  @media (prefers-reduced-motion: reduce) { .dd-pop, .dd-slide, .dd-shake, .dd-pulse { animation: none; } }
`

export function injectStyles() {
  if (document.getElementById(STYLE_ID)) return
  const style = document.createElement("style")
  style.id = STYLE_ID
  style.textContent = STYLES
  document.head.appendChild(style)
}
