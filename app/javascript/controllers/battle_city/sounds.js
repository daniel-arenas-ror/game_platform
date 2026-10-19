// Battle City sounds on the player's phone: the engine idling while the tank stands still and
// revving while it drives, a shot when their bullet leaves the barrel, an explosion when their tank
// is hit or they hit another, and a crumble when they break a brick. Web Audio, so the engine loops
// have no gap and a shot plays at once. Phones only allow sound after a touch, so the controller
// calls unlock() on every tap.
const FILES = {
  calm:  "/games/sounds/tank_calm.mp3",
  drive: "/games/sounds/tank_acceleration.mp3",
  fire:  "/games/sounds/tank_fire.mp3",
  boom:  "/games/sounds/tank_explotion.mp3",
  brick: "/games/sounds/explotion_earth.mp3"
}
// Engine loops: volume, and how much of each end to leave out of the loop (the drive sound dips
// at its ends, which would pulse every 1.5 s).
const LOOPS        = { calm: { volume: 0.6, trim: 0.05 }, drive: { volume: 0.45, trim: 0.15 } }
const FIRE_VOLUME  = 1
const BOOM_VOLUME  = 1
const BRICK_VOLUME = 0.6    // the earth file is louder than the tank one; a tank should sound bigger
const FADE_SECONDS = 0.08
const FIRE_GAP_MS  = 150    // holding Fire against a close wall shoots every tick; don't rattle
const MUTED_KEY    = "battle_city_muted"

export class TankSounds {
  constructor() {
    this.ctx     = null
    this.buffers = {}
    this.loops   = {}       // name → gain node of the running loop
    this.engine  = "off"    // "off" | "calm" | "drive"
    this.muted   = false
    try { this.muted = localStorage.getItem(MUTED_KEY) === "1" } catch {}
  }

  unlock() {
    if (!this.ctx) {
      const AudioContext = window.AudioContext || window.webkitAudioContext
      if (!AudioContext) return
      this.ctx    = new AudioContext()
      this.master = this.ctx.createGain()
      this.master.gain.value = this.muted ? 0 : 1
      this.master.connect(this.ctx.destination)
      this.load()
    }
    if (this.ctx.state === "suspended") this.ctx.resume().catch(() => {})
  }

  async load() {
    await Promise.all(Object.entries(FILES).map(async ([name, url]) => {
      try {
        const data = await (await fetch(url)).arrayBuffer()
        this.buffers[name] = await this.ctx.decodeAudioData(data)
      } catch {}   // no sound is better than a broken game
    }))
    this.applyEngine()
  }

  // "calm" while the tank stands still, "drive" while a direction is held, "off" otherwise.
  setEngine(engine) {
    this.engine = engine
    this.applyEngine()
  }

  fire() {
    const now = performance.now()
    if (now - (this.firedAt ?? -Infinity) < FIRE_GAP_MS) return
    if (this.play("fire", FIRE_VOLUME)) this.firedAt = now
  }

  explode() {
    this.play("boom", BOOM_VOLUME)
  }

  brick() {
    this.play("brick", BRICK_VOLUME)
  }

  play(name, volume) {
    const buffer = this.buffers[name]
    if (!buffer || this.ctx?.state !== "running") return false
    const source = this.ctx.createBufferSource()
    const gain   = this.ctx.createGain()
    gain.gain.value = volume
    source.buffer = buffer
    source.connect(gain).connect(this.master)
    source.start()
    return true
  }

  setMuted(muted) {
    this.muted = muted
    try { localStorage.setItem(MUTED_KEY, muted ? "1" : "0") } catch {}
    if (this.master) this.master.gain.setTargetAtTime(muted ? 0 : 1, this.ctx.currentTime, FADE_SECONDS)
  }

  close() {
    this.ctx?.close().catch(() => {})
    this.ctx = null
  }

  // Both loops run all the time once loaded; the engine state cross-fades between them.
  applyEngine() {
    if (!this.ctx) return
    Object.entries(LOOPS).forEach(([name, { volume, trim }]) => {
      const buffer = this.buffers[name]
      if (!buffer) return
      if (!this.loops[name]) this.loops[name] = this.startLoop(buffer, trim)
      const target = this.engine === name ? volume : 0
      this.loops[name].gain.setTargetAtTime(target, this.ctx.currentTime, FADE_SECONDS)
    })
  }

  startLoop(buffer, trim) {
    const source = this.ctx.createBufferSource()
    const gain   = this.ctx.createGain()
    const [start, end] = loopBounds(buffer, trim)
    source.buffer    = buffer
    source.loop      = true
    source.loopStart = start
    source.loopEnd   = end
    gain.gain.value  = 0
    source.connect(gain).connect(this.master)
    source.start(0, start)
    return gain
  }
}

// Loop points `trim` seconds in from each end, moved to where the wave crosses zero going up, so
// the jump back to the start doesn't click.
function loopBounds(buffer, trim) {
  const data = buffer.getChannelData(0)
  const rate = buffer.sampleRate
  const rise = (i) => data[i - 1] < 0 && data[i] >= 0
  let start = Math.floor(trim * rate) || 1
  let end   = data.length - 1 - Math.floor(trim * rate)
  while (start < end && !rise(start)) start++
  while (end > start && !rise(end)) end--
  if (end - start < rate * 0.5) return [0, buffer.duration]
  return [start / rate, end / rate]
}
