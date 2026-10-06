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

// Draws part of a stroke. `from` is the stroke's previous point (null when the stroke starts),
// so a stroke that arrives in several batches still joins up. Returns the last point drawn.
export function drawPoints(canvas, points, color, size, from = null) {
  const ctx   = canvas.getContext("2d")
  const width = canvas.width
  const height = canvas.height
  ctx.strokeStyle = color
  ctx.fillStyle   = color
  ctx.lineWidth   = Math.max(size * width / 1000, 1)
  ctx.lineCap     = "round"
  ctx.lineJoin    = "round"

  let last = from
  points.forEach(([ x, y ]) => {
    if (last) {
      ctx.beginPath()
      ctx.moveTo(last[0] * width, last[1] * height)
      ctx.lineTo(x * width, y * height)
      ctx.stroke()
    } else {
      // A tap with no movement is a dot.
      ctx.beginPath()
      ctx.arc(x * width, y * height, ctx.lineWidth / 2, 0, Math.PI * 2)
      ctx.fill()
    }
    last = [ x, y ]
  })
  return last
}

// strokes: [{ color, size, points }]
export function redraw(canvas, strokes) {
  clearCanvas(canvas)
  strokes.forEach(s => drawPoints(canvas, s.points, s.color, s.size))
}

// "c _ _ " pattern for the word: nil letters are hidden, spaces and punctuation are shown.
export function patternHtml(pattern, big = true) {
  if (!pattern) return ""
  const box = big ? "w-[0.9em] border-b-4" : "w-[0.8em] border-b-2"
  return pattern.map(ch => {
    if (ch === " ") return `<span class="inline-block w-[0.6em]"></span>`
    if (ch === null) return `<span class="inline-block ${box} border-current mx-[0.08em] opacity-70">&nbsp;</span>`
    return `<span class="inline-block ${box} border-transparent mx-[0.08em] text-center">${esc(ch.toUpperCase())}</span>`
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
  .dd-pop   { animation: dd-pop 0.35s ease-out; }
  .dd-slide { animation: dd-slide 0.3s cubic-bezier(0.22, 1, 0.36, 1); }
  .dd-shake { animation: dd-shake 0.4s ease-in-out; }
  @media (prefers-reduced-motion: reduce) { .dd-pop, .dd-slide, .dd-shake { animation: none; } }
`

export function injectStyles() {
  if (document.getElementById(STYLE_ID)) return
  const style = document.createElement("style")
  style.id = STYLE_ID
  style.textContent = STYLES
  document.head.appendChild(style)
}
