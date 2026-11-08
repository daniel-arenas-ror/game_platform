// Shared by the Doodle Dash host (TV) and player (artist's phone) controllers.
//
// Points are fractions of the canvas (0–1), so a drawing made on a phone fits any TV.
// Brush sizes are per 1000 px of canvas width. Both lists must match GameServices::DoodleDash.

export const PALETTE     = [ "#111827", "#ef4444", "#f97316", "#facc15", "#22c55e", "#3b82f6", "#a855f7", "#92400e", "#f8fafc", "#ffffff" ]
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

// strokes: [{ color, size, points, fill? }]
export function redraw(canvas, strokes) {
  clearCanvas(canvas)
  strokes.forEach(s => {
    if (s.fill) return floodFill(canvas, s.points[0], s.color)
    const pen = createPen(canvas, s.color, s.size)
    pen.add(s.points)
    pen.end()
  })
}

const FILL_TOLERANCE = 48  // per colour channel: how far a pixel may be from the tapped one and still fill
const EDGE_TOLERANCE = 160 // the soft pixels along a line's edge get painted too, so no pale halo is left

// Fill bucket: paints the area around `point` (fractions of the canvas) that has the tapped pixel's
// colour. Runs on every screen at its own size, so the TV and the phone get the same picture.
export function floodFill(canvas, point, color) {
  const w = canvas.width, h = canvas.height
  const x = Math.floor(point[0] * w), y = Math.floor(point[1] * h)
  if (x < 0 || y < 0 || x >= w || y >= h) return

  const ctx    = canvas.getContext("2d", { willReadFrequently: true })
  const image  = ctx.getImageData(0, 0, w, h)
  const pixels = new Uint32Array(image.data.buffer)
  const target = pixels[y * w + x]
  const paint  = packColor(color)
  if (near(target, paint, 0)) return

  const filled = new Uint8Array(w * h)
  const open   = (i) => !filled[i] && near(pixels[i], target, FILL_TOLERANCE)
  const stack  = [ y * w + x ]
  while (stack.length) {
    const i = stack.pop()
    if (!open(i)) continue
    const row = i - (i % w)
    let left = i, right = i
    while (left > row && open(left - 1)) left--
    while (right < row + w - 1 && open(right + 1)) right++
    for (let j = left; j <= right; j++) {
      pixels[j] = paint
      filled[j] = 1
      if (j >= w && open(j - w)) stack.push(j - w)
      if (j < w * (h - 1) && open(j + w)) stack.push(j + w)
    }
  }

  // One pixel more into the soft edge of the lines around the area.
  for (let i = 0; i < pixels.length; i++) {
    if (!filled[i]) continue
    const col = i % w
    for (const n of [ col > 0 ? i - 1 : -1, col < w - 1 ? i + 1 : -1, i - w, i + w ]) {
      if (n >= 0 && n < pixels.length && !filled[n] && near(pixels[n], target, EDGE_TOLERANCE)) pixels[n] = paint
    }
  }
  ctx.putImageData(image, 0, 0)
}

// "#rrggbb" as one pixel of ImageData read through a Uint32Array (little-endian: A B G R).
function packColor(hex) {
  const n = parseInt(hex.slice(1), 16)
  return ((255 << 24) | ((n & 0xff) << 16) | (n & 0xff00) | ((n >> 16) & 0xff)) >>> 0
}

function near(a, b, tolerance) {
  return Math.abs((a & 0xff) - (b & 0xff)) <= tolerance &&
         Math.abs(((a >> 8) & 0xff) - ((b >> 8) & 0xff)) <= tolerance &&
         Math.abs(((a >> 16) & 0xff) - ((b >> 16) & 0xff)) <= tolerance
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

// An emoji reaction drifting up from the bottom of `layer` (an absolute, overflow-hidden box over a
// canvas). Capped so a burst of taps can't pile up.
export function floatEmoji(layer, emoji, calm = false) {
  if (!layer || layer.childElementCount > 30) return
  const el = document.createElement("span")
  el.textContent = emoji
  el.className = "absolute bottom-0 text-5xl select-none"
  el.style.left = `${8 + Math.random() * 80}%`
  layer.appendChild(el)
  const rise = layer.clientHeight * (0.55 + Math.random() * 0.35)
  const drift = (Math.random() - 0.5) * 60
  const frames = calm
    ? [ { opacity: 1 }, { opacity: 0 } ]
    : [ { transform: "translate(0, 0) scale(.6)", opacity: 0 },
        { transform: `translate(${drift / 3}px, -${rise * 0.2}px) scale(1.1)`, opacity: 1, offset: 0.15 },
        { transform: `translate(${drift}px, -${rise}px) scale(1)`, opacity: 0 } ]
  el.animate(frames, { duration: 2200, easing: "ease-out" }).finished.then(() => el.remove(), () => el.remove())
}

