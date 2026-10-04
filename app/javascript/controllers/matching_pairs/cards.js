// Card rendering shared by the Matching Pairs host and player controllers.
// A card item is { key, label, kind: "image" | "text", src }.

export const BACK_COLOR  = "linear-gradient(135deg, #e11d48, #9f1239)"
export const FACE_COLOR  = "#f1f5f9"
export const MATCH_RING  = "0 0 0 3px #fb7185"
export const MISS_COLOR  = "#fecaca"

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

export function backHtml() {
  return `<span style="font-weight:900;font-size:var(--card-font);color:rgba(255,255,255,.35)">?</span>`
}

// Builds `cols × rows` face-down cards inside `el`. `fontSize` is a CSS length for faces and backs.
export function buildBoard(el, cols, rows, fontSize) {
  el.style.gridTemplateColumns = `repeat(${cols}, minmax(0, 1fr))`
  el.style.setProperty("--card-font", fontSize)
  el.innerHTML = ""

  for (let i = 0; i < cols * rows; i++) {
    const card = document.createElement("div")
    card.dataset.index = i
    card.style.cssText = `
      aspect-ratio: 1; display: flex; align-items: center; justify-content: center;
      border-radius: 12px; overflow: hidden; user-select: none;
      transition: background 0.2s ease, box-shadow 0.2s ease, transform 0.15s ease, opacity 0.3s ease;
    `
    showBack(card)
    el.appendChild(card)
  }
}

export function cardAt(el, index) {
  return el.querySelector(`[data-index="${index}"]`)
}

export function showBack(card) {
  card.dataset.state = "down"
  card.style.background = BACK_COLOR
  card.style.boxShadow  = "none"
  card.style.opacity    = "1"
  card.innerHTML = backHtml()
}

export function showFace(card, item, state = "up") {
  card.dataset.state = state
  card.style.background = state === "miss" ? MISS_COLOR : FACE_COLOR
  card.style.boxShadow  = state === "matched" ? MATCH_RING : "none"
  card.innerHTML = faceHtml(item)
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
