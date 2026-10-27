// Shared by the Tug of War TV and phone controllers: team names and colours, the pull animations
// and the TV's sounds.
import { t } from "controllers/shared/i18n"
import { Sounds } from "controllers/haunted_house/common"

export const TEAMS     = [ "red", "blue" ]
export const TEAM_ICON = { red: "🔴", blue: "🔵" }
// Full class names, so Tailwind finds them.
export const TEAM_LOOK = {
  red:  { text: "text-red-400",  ring: "ring-red-500",  solid: "bg-red-500",  page: "bg-red-950" },
  blue: { text: "text-blue-400", ring: "ring-blue-500", solid: "bg-blue-500", page: "bg-blue-950" }
}

export const teamName  = (team) => t(`tug_of_war.teams.${team}`)

// The flag on the rope: −100 (Red's end) … +100 (Blue's end) → 0 … 100 % along a track.
export const ropePercent = (position) => 50 + Math.max(-100, Math.min(100, Number(position) || 0)) / 2

// Pop-ins, the pull jolt, the floating "+1" and the frozen shake. Injected once per page.
export function injectStyles() {
  if (document.getElementById("tug-of-war-styles")) return

  const style = document.createElement("style")
  style.id = "tug-of-war-styles"
  style.textContent = `
    .tw-pop { animation: tw-pop .35s ease-out both; }
    @keyframes tw-pop { 0% { transform: scale(.6); opacity: 0 } 70% { transform: scale(1.08); opacity: 1 } 100% { transform: scale(1) } }
    .tw-tug { animation: tw-tug .4s ease-out; }
    @keyframes tw-tug { 0%, 100% { transform: translateX(0) rotate(0) } 35% { transform: translateX(calc(var(--dir) * 14px)) rotate(calc(var(--dir) * -12deg)) } }
    .tw-float { animation: tw-float 1.4s ease-out forwards; }
    @keyframes tw-float { 0% { opacity: 0; transform: translate(-50%, 0) scale(.7) } 15% { opacity: 1; transform: translate(-50%, -12px) scale(1.1) } 100% { opacity: 0; transform: translate(-50%, -70px) scale(1) } }
    .tw-shake { animation: tw-shake .45s ease-in-out 2; }
    @keyframes tw-shake { 0%, 100% { transform: translateX(0) } 25% { transform: translateX(-10px) rotate(-6deg) } 75% { transform: translateX(10px) rotate(6deg) } }
    .tw-flash { animation: tw-flash .5s ease-out; }
    @keyframes tw-flash { 0% { opacity: 1 } 100% { opacity: 0 } }
    .tw-toast { animation: tw-toast 3s ease-in-out forwards; }
    @keyframes tw-toast { 0% { opacity: 0; transform: translateY(8px) } 8%, 85% { opacity: 1; transform: none } 100% { opacity: 0 } }
    .tw-rope { transition: transform .45s cubic-bezier(.22, 1, .36, 1); }
    @media (prefers-reduced-motion: reduce) {
      .tw-pop, .tw-tug, .tw-float, .tw-shake, .tw-flash, .tw-toast { animation: none; }
      .tw-float { opacity: 0; }
      .tw-rope { transition: none; }
    }
  `
  document.head.appendChild(style)
}

// Restarts a CSS animation on an element.
export function replay(el, className) {
  el.classList.remove(className)
  void el.offsetWidth
  el.classList.add(className)
}

// The TV's sounds: Haunted House's drumroll and chime, plus a pull (a low thud, higher for Blue)
// and the countdown beeps.
export class TugSounds extends Sounds {
  pull(team) {
    if (!this.ready) return
    const ctx = this.ctx, now = ctx.currentTime
    const osc = ctx.createOscillator(), gain = ctx.createGain()
    osc.type = "triangle"
    osc.frequency.setValueAtTime(team === "red" ? 180 : 240, now)
    osc.frequency.exponentialRampToValueAtTime(team === "red" ? 90 : 120, now + 0.15)
    gain.gain.setValueAtTime(0.0001, now)
    gain.gain.exponentialRampToValueAtTime(0.35, now + 0.01)
    gain.gain.exponentialRampToValueAtTime(0.0001, now + 0.2)
    osc.connect(gain).connect(this.master)
    osc.start(now); osc.stop(now + 0.22)
  }

  beep(high = false) {
    if (!this.ready) return
    const ctx = this.ctx, now = ctx.currentTime
    const osc = ctx.createOscillator(), gain = ctx.createGain()
    osc.type = "square"
    osc.frequency.value = high ? 880 : 440
    gain.gain.setValueAtTime(0.0001, now)
    gain.gain.exponentialRampToValueAtTime(0.15, now + 0.01)
    gain.gain.exponentialRampToValueAtTime(0.0001, now + (high ? 0.5 : 0.18))
    osc.connect(gain).connect(this.master)
    osc.start(now); osc.stop(now + 0.55)
  }
}
