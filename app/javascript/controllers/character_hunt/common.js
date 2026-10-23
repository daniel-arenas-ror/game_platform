// Shared by the Character Hunt TV and phone controllers.
import { t } from "controllers/shared/i18n"

// Finders' places: "🥇 1st".
export const placeLabel = (place) => t(`character_hunt.places.${place}`)

// The pop-in and the frozen shake. Injected once per page.
export function injectStyles() {
  if (document.getElementById("character-hunt-styles")) return

  const style = document.createElement("style")
  style.id = "character-hunt-styles"
  style.textContent = `
    .ch-pop { animation: ch-pop .35s ease-out both; }
    @keyframes ch-pop { 0% { transform: scale(.6); opacity: 0 } 70% { transform: scale(1.08); opacity: 1 } 100% { transform: scale(1) } }
    .ch-shake { animation: ch-shake .45s ease-in-out 2; }
    @keyframes ch-shake { 0%, 100% { transform: translateX(0) } 25% { transform: translateX(-10px) rotate(-6deg) } 75% { transform: translateX(10px) rotate(6deg) } }
    .ch-toast { animation: ch-toast 4s ease-in-out forwards; }
    @keyframes ch-toast { 0% { opacity: 0; transform: translateY(8px) } 8%, 85% { opacity: 1; transform: none } 100% { opacity: 0 } }
    @media (prefers-reduced-motion: reduce) { .ch-pop, .ch-shake, .ch-toast { animation: none; } }
  `
  document.head.appendChild(style)
}

// Restarts a CSS animation on an element.
export function replay(el, className) {
  el.classList.remove(className)
  void el.offsetWidth
  el.classList.add(className)
}
