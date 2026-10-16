// Shared by the Monster Mash TV and phone controllers: drawing a whole monster (head, body and
// legs stacked) from its strokes, and the slime-green styles. Drawing itself reuses Doodle Dash's
// pen, so a monster drawn on a phone looks the same on every screen.
import { fitCanvas, redraw } from "controllers/doodle_dash/drawing"

export const PARTS = ["head", "body", "legs"]

// Builds the three stacked canvases of `monster` inside `container` and draws them. With
// `animate`, the parts slide in one after another (the reveal), `stepMs` apart.
export function drawMonster(container, monster, { animate = false, stepMs = 1400, onPart } = {}) {
  container.replaceChildren()
  const stack = document.createElement("div")
  stack.className = "mm-stack flex flex-col w-full rounded-2xl overflow-hidden bg-white shadow-2xl"
  container.append(stack)

  const canvases = PARTS.map(part => {
    const canvas = document.createElement("canvas")
    canvas.className = "block w-full"
    canvas.style.aspectRatio = "4 / 3"
    canvas.dataset.part = part
    if (animate) canvas.style.visibility = "hidden"
    stack.append(canvas)
    return canvas
  })

  // Sized once they're in the page, so the buffers match what's on screen.
  requestAnimationFrame(() => {
    canvases.forEach((canvas, i) => {
      fitCanvas(canvas)
      redraw(canvas, monster.parts?.[PARTS[i]] || [])
    })
    if (!animate) return
    canvases.forEach((canvas, i) => {
      setTimeout(() => {
        canvas.style.visibility = ""
        canvas.classList.add("mm-drop")
        onPart?.(PARTS[i], i)
      }, i * stepMs)
    })
  })
  return stack
}

// Redraws canvases already in the page (after a resize).
export function redrawMonster(container, monster) {
  container.querySelectorAll("canvas[data-part]").forEach(canvas => {
    fitCanvas(canvas)
    redraw(canvas, monster.parts?.[canvas.dataset.part] || [])
  })
}

export function injectMonsterStyles() {
  if (document.getElementById("monster-mash-styles")) return
  const style = document.createElement("style")
  style.id = "monster-mash-styles"
  style.textContent = `
    .mm-bg { background: radial-gradient(ellipse at top, #14532d 0%, #0b1a12 50%, #020617 100%); }
    .mm-drop { animation: mm-drop .7s cubic-bezier(.22, 1, .36, 1) both; }
    @keyframes mm-drop { from { transform: translateY(-40px) scale(.9); opacity: 0 } to { transform: none; opacity: 1 } }
    .mm-pop { animation: mm-pop .5s ease-out both; }
    @keyframes mm-pop { 0% { transform: scale(.6); opacity: 0 } 60% { transform: scale(1.1); opacity: 1 } 100% { transform: scale(1) } }
    .mm-wobble { animation: mm-wobble 3s ease-in-out infinite; }
    @keyframes mm-wobble { 0%, 100% { transform: rotate(-2deg) } 50% { transform: rotate(2deg) } }
    @media (prefers-reduced-motion: reduce) { .mm-drop, .mm-pop, .mm-wobble { animation: none; } }
  `
  document.head.appendChild(style)
}
