// Every game's sound goes through here. On an iPhone, Safari and Chrome (which runs on Safari there)
// play sound only after a tap on the current page, the tap that opened it doesn't count, and a
// finger going down isn't a tap: only lifting it is. So:
// - the page has one AudioContext, and any tap anywhere starts it. The listeners stay, since iOS can
//   stop it again after the screen locks or a call;
// - mp3 files play through it too (soundFile), so one tap turns on every sound, also the ones the
//   server starts later;
// - iOS 17+ keeps the sound on with the side switch on silent ("playback").
// A sound asked for while it's still off is skipped, not queued, and shows the "Tap for sound" chip.

const GESTURES  = [ "pointerup", "touchend", "click", "keydown" ]
const WAIT_MS   = 300 // how long a sound waits for the tap that's starting the context
const CHANGE    = "sound:change"
const BLOCKED   = "sound:blocked"

let context = null

export function audioContext() {
  if (!context) {
    const AudioCtx = window.AudioContext || window.webkitAudioContext
    if (!AudioCtx) return null
    context = new AudioCtx()
    context.onstatechange = () => window.dispatchEvent(new Event(CHANGE))
  }
  return context
}

export const soundOn = () => context?.state === "running"

export function unlockSound() {
  const ctx = audioContext()
  if (ctx && ctx.state !== "running") ctx.resume().catch(() => {})
}

// For code that plays at once (the Web Audio games' `ready`): says whether it can, and shows the
// chip when it can't.
export function canPlay() {
  if (soundOn()) return true
  unlockSound()
  window.dispatchEvent(new Event(BLOCKED))
  return false
}

// Waits a moment for a tap that is starting the context (the sound of the tap itself).
async function started() {
  const ctx = audioContext()
  if (!ctx) return false
  for (let waited = 0; ctx.state !== "running" && waited < WAIT_MS; waited += 50) {
    ctx.resume().catch(() => {})
    await new Promise((resolve) => setTimeout(resolve, 50))
  }
  return canPlay()
}

try { if (navigator.audioSession) navigator.audioSession.type = "playback" } catch {}
GESTURES.forEach((name) => document.addEventListener(name, unlockSound, { capture: true, passive: true }))
document.addEventListener("visibilitychange", () => { if (document.visibilityState === "visible" && context) unlockSound() })

// ── mp3 files ───────────────────────────────────────────────────────────────

const buffers = new Map() // url → Promise of the decoded sound (null when it can't load)

function load(url) {
  if (!buffers.has(url)) {
    buffers.set(url, fetch(url)
      .then((response) => response.arrayBuffer())
      .then((data) => audioContext().decodeAudioData(data))
      .catch(() => null)) // no sound is better than a broken game
  }
  return buffers.get(url)
}

// Stands in for `new Audio(url)` with the parts the games use: play() (always from the start, and
// the promise never rejects), pause(), loop, and `currentTime = 0` (accepted, nothing else needed).
class SoundFile {
  constructor(url) {
    this.url         = url
    this.loop        = false
    this.currentTime = 0
    this.source      = null
    this.plays       = 0
    if (audioContext()) load(url)
  }

  async play() {
    const play = ++this.plays
    const buffer = audioContext() && await load(this.url)
    if (!buffer || !(await started()) || play !== this.plays) return

    this.stop()
    const source = context.createBufferSource()
    source.buffer = buffer
    source.loop   = this.loop
    source.connect(context.destination)
    source.onended = () => { if (this.source === source) this.source = null }
    source.start()
    this.source = source
  }

  pause() {
    this.plays++ // a play still loading doesn't start after this
    this.stop()
  }

  stop() {
    try { this.source?.stop() } catch {}
    this.source = null
  }
}

export const soundFile = (url) => new SoundFile(url)

export { CHANGE as SOUND_CHANGE, BLOCKED as SOUND_BLOCKED }
