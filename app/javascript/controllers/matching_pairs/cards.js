// Card rendering shared by the Matching Pairs host and player controllers.
// A card item is { key, label, kind: "image" | "text", src }.
//
// Each card is a 3D flip card:  [data-index] (perspective, pulse/shake)
//                                 └ .mp-inner (rotates 180° when face up)
//                                     ├ .mp-back  (rose, "?")
//                                     └ .mp-face  (the item)

export const BACK_COLOR  = "linear-gradient(135deg, #e11d48, #9f1239)"
export const FACE_COLOR  = "#f1f5f9"
export const MATCH_RING  = "0 0 0 3px #fb7185"
export const MISS_COLOR  = "#fecaca"

export const FLIP_MS = 250

const STYLE_ID = "matching-pairs-styles"
const STYLES = `
  .mp-card  { perspective: 600px; aspect-ratio: 1; user-select: none; -webkit-user-select: none; }
  .mp-inner { position: relative; width: 100%; height: 100%; transform-style: preserve-3d;
              transition: transform ${FLIP_MS}ms ease-out; }
  .mp-card[data-state="up"] .mp-inner, .mp-card[data-state="matched"] .mp-inner,
  .mp-card[data-state="miss"] .mp-inner { transform: rotateY(180deg); }
  .mp-back, .mp-face { position: absolute; inset: 0; display: flex; align-items: center; justify-content: center;
                       border-radius: 12px; overflow: hidden; backface-visibility: hidden; -webkit-backface-visibility: hidden;
                       transition: background 0.2s ease, box-shadow 0.2s ease; }
  .mp-back { background: ${BACK_COLOR}; }
  .mp-face { background: ${FACE_COLOR}; transform: rotateY(180deg); }
  .mp-card[data-state="matched"] .mp-face { box-shadow: inset ${MATCH_RING}; }
  .mp-card[data-state="miss"] .mp-face    { background: ${MISS_COLOR}; }
  .mp-card.mp-dim { opacity: 0.45; transition: opacity 0.3s ease; }

  @keyframes mp-pulse { 0%, 100% { transform: scale(1) } 50% { transform: scale(1.12) } }
  @keyframes mp-shake { 0%, 100% { transform: translateX(0) } 20%, 60% { transform: translateX(-5px) } 40%, 80% { transform: translateX(5px) } }
  @keyframes mp-pop   { 0% { transform: scale(0.5); opacity: 0 } 60% { transform: scale(1.2); opacity: 1 } 100% { transform: scale(1) } }
  @keyframes mp-slide { from { transform: translateY(16px); opacity: 0 } to { transform: translateY(0); opacity: 1 } }
  .mp-pulse { animation: mp-pulse 0.35s ease-out ${FLIP_MS}ms }
  .mp-shake { animation: mp-shake 0.3s ease-in-out ${FLIP_MS}ms }
  .mp-pop   { animation: mp-pop 0.4s ease-out }
  .mp-slide { animation: mp-slide 0.3s ease-out }

  @media (prefers-reduced-motion: reduce) {
    .mp-inner { transition: none; }
    .mp-pulse, .mp-shake, .mp-pop, .mp-slide { animation: none; }
  }
`

export function injectStyles() {
  if (document.getElementById(STYLE_ID)) return
  const style = document.createElement("style")
  style.id = STYLE_ID
  style.textContent = STYLES
  document.head.appendChild(style)
}

export function esc(str) {
  return String(str).replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;").replace(/"/g, "&quot;")
}

// Each number gets its own colour so pairs are easier to tell apart at a glance.
function numberColor(label) {
  return `hsl(${(Number(label) * 47) % 360}, 75%, 40%)`
}

export function faceHtml(item) {
  if (item.kind === "image") {
    const flag = item.key.startsWith("flags:")
    return `<img src="${esc(item.src)}" alt="${esc(item.label)}" draggable="false"
                 style="width:${flag ? 86 : 72}%;height:${flag ? 86 : 72}%;object-fit:contain;pointer-events:none;
                        ${flag ? "filter:drop-shadow(0 1px 2px rgba(0,0,0,.35));" : ""}">`
  }
  return `<span style="font-weight:900;font-family:ui-monospace,monospace;font-size:var(--card-font);
                       color:${numberColor(item.label)}">${esc(item.label)}</span>`
}

// Builds `cols × rows` face-down cards inside `el`. `fontSize` is a CSS length for faces and backs.
export function buildBoard(el, cols, rows, fontSize) {
  injectStyles()
  el.style.gridTemplateColumns = `repeat(${cols}, minmax(0, 1fr))`
  el.style.setProperty("--card-font", fontSize)
  el.innerHTML = ""

  for (let i = 0; i < cols * rows; i++) {
    const card = document.createElement("div")
    card.className = "mp-card"
    card.dataset.index = i
    card.dataset.state = "down"
    card.innerHTML = `
      <div class="mp-inner">
        <div class="mp-back"><span style="font-weight:900;font-size:var(--card-font);color:rgba(255,255,255,.35)">?</span></div>
        <div class="mp-face"></div>
      </div>`
    el.appendChild(card)
  }
}

export function cardAt(el, index) {
  return el.querySelector(`[data-index="${index}"]`)
}

// Turns a card face down. The face is cleared once it's hidden, so it can't be peeked at.
export function showBack(card) {
  if (!card) return
  card.dataset.state = "down"
  card.classList.remove("mp-dim")
  setTimeout(() => { if (card.dataset.state === "down") card.querySelector(".mp-face").innerHTML = "" }, FLIP_MS)
}

// state: "up" | "matched" | "miss". Only rewrites the face when the item changes, so an
// already-visible image doesn't reload.
export function showFace(card, item, state = "up") {
  if (!card || !item) return
  const face = card.querySelector(".mp-face")
  if (face.dataset.key !== item.key || !face.innerHTML) {
    face.innerHTML  = faceHtml(item)
    face.dataset.key = item.key
  }
  card.dataset.state = state
}

// Turns every card over one after another, `stepMs` apart.
export function cascade(el, fn, stepMs = 25) {
  el.querySelectorAll("[data-index]").forEach((card, i) => setTimeout(() => fn(card, i), i * stepMs))
}

export function restartAnimation(el, className) {
  if (!el) return
  el.classList.remove(className)
  void el.offsetWidth // force reflow so the animation plays again
  el.classList.add(className)
}

// Loads images ahead of time so a flipped card shows instantly.
export function preload(urls) {
  return (urls || []).map(src => { const img = new Image(); img.src = src; return img })
}

// Ranks with ties: equal scores share a place (1, 1, 3 …).
export function ranked(scores) {
  const entries = Object.entries(scores || {}).sort((a, b) => b[1] - a[1])
  return entries.map(([id, pts]) => ({ id, pts, place: 1 + entries.filter(([, p]) => p > pts).length }))
}

export const MEDALS = { 1: "🥇", 2: "🥈", 3: "🥉" }
