// Shared by the Haunted House TV and phone controllers: the spooky look, the countdown and the
// sounds. The sounds are made with the Web Audio API (no files to load): a night drone with wind,
// a scream when someone is scared out, a drumroll for the vote and a chime for the winners.
import { t } from "controllers/shared/i18n"

export const ROLE_ICON = { ghost: "👻", medium: "🔮", guest: "🎃" }

export const roleName  = (role) => t(`haunted_house.roles.${role}`)
export const placeName = (place) => t(`haunted_house.places.${place}`)

// Whole seconds left in the phase, counted on this device from what the server said.
export function startCountdown(el, seconds, onTick) {
  clearInterval(el._hhTimer)
  if (seconds == null) { el.textContent = ""; return }

  const ends = Date.now() + seconds * 1000
  const tick = () => {
    const left = Math.max(0, Math.ceil((ends - Date.now()) / 1000))
    el.textContent = left >= 60 ? `${Math.floor(left / 60)}:${String(left % 60).padStart(2, "0")}` : String(left)
    el.style.color = left <= 5 ? "#f87171" : left <= 10 ? "#fb923c" : ""
    onTick?.(left)
    if (left <= 0) clearInterval(el._hhTimer)
  }
  tick()
  el._hhTimer = setInterval(tick, 250)
}

export function stopCountdown(el) {
  clearInterval(el._hhTimer)
  el.textContent = ""
}

// The night sky, the fog and the floating icon. Injected once per page.
export function injectStyles() {
  if (document.getElementById("haunted-house-styles")) return

  const style = document.createElement("style")
  style.id = "haunted-house-styles"
  style.textContent = `
    .hh-night { background: radial-gradient(ellipse at top, #2e1065 0%, #0b0618 55%, #020617 100%); position: relative; }
    .hh-night::before { content: ""; position: absolute; inset: 0 -10%; pointer-events: none; z-index: 0;
      background: radial-gradient(ellipse at 20% 110%, rgba(148,163,184,.18), transparent 55%),
                  radial-gradient(ellipse at 80% 115%, rgba(148,163,184,.14), transparent 50%);
      animation: hh-fog 14s ease-in-out infinite alternate; }
    .hh-night.hh-day { background: radial-gradient(ellipse at top, #7c2d12 0%, #1c1917 60%, #0c0a09 100%); }
    @keyframes hh-fog { from { transform: translateX(-4%); opacity: .7 } to { transform: translateX(4%); opacity: 1 } }
    .hh-float { animation: hh-float 4s ease-in-out infinite; }
    @keyframes hh-float { 0%, 100% { transform: translateY(0) } 50% { transform: translateY(-14px) } }
    .hh-shake { animation: hh-shake .5s ease-in-out 2; }
    @keyframes hh-shake { 0%, 100% { transform: translateX(0) } 25% { transform: translateX(-12px) rotate(-3deg) } 75% { transform: translateX(12px) rotate(3deg) } }
    .hh-appear { animation: hh-appear .6s ease-out both; }
    @keyframes hh-appear { from { opacity: 0; transform: scale(.85) } to { opacity: 1; transform: scale(1) } }
  `
  document.head.appendChild(style)
}

// ── Sounds (TV only) ───────────────────────────────────────────────────────

export class Sounds {
  constructor() {
    this.enabled = true
    this.ctx     = null
    this.drone   = null
  }

  // Browsers only allow sound after a tap on the page; any tap (e.g. Sound, Skip) unlocks it.
  unlock() {
    if (!this.ctx) {
      const AudioCtx = window.AudioContext || window.webkitAudioContext
      if (!AudioCtx) return
      this.ctx    = new AudioCtx()
      this.master = this.ctx.createGain()
      this.master.gain.value = 0.6
      this.master.connect(this.ctx.destination)
    }
    if (this.ctx.state === "suspended") this.ctx.resume().catch(() => {})
  }

  toggle() {
    this.enabled = !this.enabled
    this.unlock()
    if (this.master) this.master.gain.value = this.enabled ? 0.6 : 0
    return this.enabled
  }

  get ready() {
    if (!this.ctx) this.unlock()
    return this.ctx && this.ctx.state === "running"
  }

  // Low wind and a slow, wavering drone, until stopNight().
  startNight() {
    if (!this.ready || this.drone) return
    const ctx = this.ctx, now = ctx.currentTime
    const out = ctx.createGain()
    out.gain.setValueAtTime(0, now)
    out.gain.linearRampToValueAtTime(0.5, now + 2)
    out.connect(this.master)

    const osc = ctx.createOscillator(), lfo = ctx.createOscillator(), lfoGain = ctx.createGain()
    osc.type = "sawtooth"; osc.frequency.value = 55
    lfo.frequency.value = 0.15; lfoGain.gain.value = 6
    lfo.connect(lfoGain).connect(osc.frequency)
    const low = ctx.createBiquadFilter(); low.type = "lowpass"; low.frequency.value = 220
    const droneGain = ctx.createGain(); droneGain.gain.value = 0.25
    osc.connect(low).connect(droneGain).connect(out)

    const wind = this.noise(), band = ctx.createBiquadFilter(), sweep = ctx.createOscillator(), sweepGain = ctx.createGain()
    band.type = "bandpass"; band.frequency.value = 500; band.Q.value = 0.8
    sweep.frequency.value = 0.08; sweepGain.gain.value = 300
    sweep.connect(sweepGain).connect(band.frequency)
    const windGain = ctx.createGain(); windGain.gain.value = 0.35
    wind.connect(band).connect(windGain).connect(out)

    ;[osc, lfo, wind, sweep].forEach(n => n.start())
    this.drone = { out, nodes: [osc, lfo, wind, sweep] }
  }

  stopNight() {
    if (!this.drone) return
    const { out, nodes } = this.drone, now = this.ctx.currentTime
    out.gain.cancelScheduledValues(now)
    out.gain.setValueAtTime(out.gain.value, now)
    out.gain.linearRampToValueAtTime(0, now + 1.5)
    nodes.forEach(n => n.stop(now + 1.6))
    this.drone = null
  }

  // A falling, wobbling shriek.
  scream() {
    if (!this.ready) return
    const ctx = this.ctx, now = ctx.currentTime
    const osc = ctx.createOscillator(), vib = ctx.createOscillator(), vibGain = ctx.createGain(), gain = ctx.createGain()
    osc.type = "sawtooth"
    osc.frequency.setValueAtTime(1300, now)
    osc.frequency.exponentialRampToValueAtTime(350, now + 1.2)
    vib.frequency.value = 9; vibGain.gain.value = 40
    vib.connect(vibGain).connect(osc.frequency)
    gain.gain.setValueAtTime(0.0001, now)
    gain.gain.exponentialRampToValueAtTime(0.35, now + 0.05)
    gain.gain.exponentialRampToValueAtTime(0.0001, now + 1.3)
    osc.connect(gain).connect(this.master)
    ;[osc, vib].forEach(n => { n.start(now); n.stop(now + 1.4) })
  }

  // A snare roll that speeds up, for `seconds`.
  drumroll(seconds = 2.5) {
    if (!this.ready) return
    const ctx = this.ctx, start = ctx.currentTime
    let at = 0, gap = 0.12
    while (at < seconds) {
      this.hit(start + at, 0.08 + 0.12 * (at / seconds))
      at += gap
      gap = Math.max(0.04, gap * 0.94)
    }
    this.hit(start + seconds + 0.05, 0.4, 0.4) // the final crash
  }

  // Rising notes for the winners.
  chime() {
    if (!this.ready) return
    const now = this.ctx.currentTime
    ;[392, 494, 587, 784].forEach((freq, i) => {
      const osc = this.ctx.createOscillator(), gain = this.ctx.createGain(), at = now + i * 0.16
      osc.type = "triangle"; osc.frequency.value = freq
      gain.gain.setValueAtTime(0.0001, at)
      gain.gain.exponentialRampToValueAtTime(0.3, at + 0.02)
      gain.gain.exponentialRampToValueAtTime(0.0001, at + 0.9)
      osc.connect(gain).connect(this.master)
      osc.start(at); osc.stop(at + 1)
    })
  }

  hit(at, volume, length = 0.08) {
    const src = this.noise(), gain = this.ctx.createGain(), high = this.ctx.createBiquadFilter()
    high.type = "highpass"; high.frequency.value = 1200
    gain.gain.setValueAtTime(volume, at)
    gain.gain.exponentialRampToValueAtTime(0.0001, at + length)
    src.connect(high).connect(gain).connect(this.master)
    src.start(at); src.stop(at + length + 0.02)
  }

  noise() {
    if (!this.noiseBuffer) {
      const length = this.ctx.sampleRate * 2
      this.noiseBuffer = this.ctx.createBuffer(1, length, this.ctx.sampleRate)
      const data = this.noiseBuffer.getChannelData(0)
      for (let i = 0; i < length; i++) data[i] = Math.random() * 2 - 1
    }
    const src = this.ctx.createBufferSource()
    src.buffer = this.noiseBuffer
    src.loop = true
    return src
  }

  close() {
    this.ctx?.close().catch(() => {})
  }
}
