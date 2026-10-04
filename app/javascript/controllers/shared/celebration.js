// The winner celebration every game plays on the winning player's phone at game over:
// a burst of falling confetti plus a pop-in on the title. Respects prefers-reduced-motion.
//
//   import { celebrateWin, isTopScore } from "controllers/shared/celebration"
//   if (isTopScore(data.scores, this.playerIdValue)) celebrateWin(this.gameOverTitleTarget)

const STYLE_ID = "shared-celebration-styles"
const STYLES = `
  @keyframes celebrate-fall { from { transform: translate(0, -10vh) rotate(0) } to { transform: translate(var(--drift), 110vh) rotate(var(--spin)) } }
  @keyframes celebrate-pop  { 0% { transform: scale(0.5); opacity: 0 } 60% { transform: scale(1.2); opacity: 1 } 100% { transform: scale(1) } }
  .celebrate-confetti { position: fixed; top: 0; z-index: 100; pointer-events: none; animation: celebrate-fall linear forwards; }
  .celebrate-pop      { animation: celebrate-pop 0.4s ease-out; }

  @media (prefers-reduced-motion: reduce) {
    .celebrate-confetti { display: none; }
    .celebrate-pop      { animation: none; }
  }
`

const COLORS = [ "#fb7185", "#f43f5e", "#facc15", "#4ade80", "#38bdf8", "#c084fc" ]

function injectStyles() {
  if (document.getElementById(STYLE_ID)) return
  const style = document.createElement("style")
  style.id = STYLE_ID
  style.textContent = STYLES
  document.head.appendChild(style)
}

// A short burst of falling confetti across the whole screen.
export function confetti(count = 60) {
  injectStyles()
  for (let i = 0; i < count; i++) {
    const bit  = document.createElement("div")
    const size = 6 + Math.random() * 6
    bit.className = "celebrate-confetti"
    bit.style.cssText = `
      left: ${Math.random() * 100}vw; width: ${size}px; height: ${size * 1.6}px;
      background: ${COLORS[i % COLORS.length]}; border-radius: 2px;
      animation-duration: ${1.6 + Math.random() * 1.4}s; animation-delay: ${Math.random() * 0.4}s;
      --drift: ${(Math.random() - 0.5) * 30}vw; --spin: ${(Math.random() - 0.5) * 1080}deg;
    `
    document.body.appendChild(bit)
    setTimeout(() => bit.remove(), 3500)
  }
}

// Plays the pop-in on `el` (restarting it if it already ran).
export function pop(el) {
  if (!el) return
  injectStyles()
  el.classList.remove("celebrate-pop")
  void el.offsetWidth // force reflow so the animation plays again
  el.classList.add("celebrate-pop")
}

// Confetti, plus a pop on `el` (the game-over title or medal), when given.
export function celebrateWin(el = null) {
  pop(el)
  confetti()
}

// True when `playerId` has the highest score — tied players all count as winners.
export function isTopScore(scores, playerId) {
  const values = Object.values(scores || {}).map(Number)
  return values.length > 0 && playerId in scores && Number(scores[playerId]) === Math.max(...values)
}
