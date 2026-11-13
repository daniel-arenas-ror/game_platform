import { Controller } from "@hotwired/stimulus"
import { audioContext, canPlay, SOUND_CHANGE } from "controllers/shared/sound"

// Christmas mode: the opening of "Jingle Bells" (public domain, 1857) with sleigh bells, on the TV when
// a game screen opens (rooms/playing, host only). Web Audio through the page's shared context. When the
// sound is still off, it plays on the tap that turns it on, if that comes within WAIT_MS.
const WAIT_MS = 10000
const BEAT    = 0.24 // seconds per beat
const VOLUME  = 0.3

// "Jin-gle bells, jin-gle bells, jin-gle all the way": [frequency, beats].
const E5 = 659.25, G5 = 783.99, C5 = 523.25, D5 = 587.33
const MELODY = [ [ E5, 1 ], [ E5, 1 ], [ E5, 2 ], [ E5, 1 ], [ E5, 1 ], [ E5, 2 ],
                 [ E5, 1 ], [ G5, 1 ], [ C5, 1.5 ], [ D5, 0.5 ], [ E5, 4 ] ]

export default class extends Controller {
  connect() {
    if (canPlay()) { this.play(); return }

    this.onChange = () => {
      if (audioContext()?.state !== "running") return
      this.stopWaiting()
      this.play()
    }
    window.addEventListener(SOUND_CHANGE, this.onChange)
    this.timeout = setTimeout(() => this.stopWaiting(), WAIT_MS)
  }

  disconnect() {
    this.stopWaiting()
  }

  stopWaiting() {
    clearTimeout(this.timeout)
    if (this.onChange) window.removeEventListener(SOUND_CHANGE, this.onChange)
    this.onChange = null
  }

  play() {
    const ctx = audioContext()
    if (!ctx) return
    const out = ctx.createGain()
    out.gain.value = VOLUME
    out.connect(ctx.destination)

    let at = ctx.currentTime + 0.05
    MELODY.forEach(([ frequency, beats ]) => {
      this.note(ctx, out, frequency, at, beats * BEAT)
      at += beats * BEAT
    })
    // Sleigh bells: a shake on every beat, a little louder on the first of each bar.
    const beats = MELODY.reduce((sum, [ , b ]) => sum + b, 0)
    for (let i = 0; i < beats; i++) this.bells(ctx, out, ctx.currentTime + 0.05 + i * BEAT, i % 4 === 0 ? 0.5 : 0.3)
  }

  // A bell-like note: a sine with a quiet octave above, fading out.
  note(ctx, out, frequency, at, seconds) {
    [ [ frequency, 0.6 ], [ frequency * 2, 0.15 ] ].forEach(([ f, level ]) => {
      const osc = ctx.createOscillator(), gain = ctx.createGain()
      osc.type = "sine"
      osc.frequency.value = f
      gain.gain.setValueAtTime(0.0001, at)
      gain.gain.exponentialRampToValueAtTime(level, at + 0.01)
      gain.gain.exponentialRampToValueAtTime(0.0001, at + Math.max(seconds, 0.2) * 0.95)
      osc.connect(gain).connect(out)
      osc.start(at)
      osc.stop(at + seconds)
    })
  }

  // A short burst of high, filtered noise: the jingle of sleigh bells.
  bells(ctx, out, at, level) {
    const length = Math.floor(ctx.sampleRate * 0.12)
    const buffer = ctx.createBuffer(1, length, ctx.sampleRate)
    const data   = buffer.getChannelData(0)
    for (let i = 0; i < length; i++) data[i] = (Math.random() * 2 - 1) * (1 - i / length)

    const noise = ctx.createBufferSource(), filter = ctx.createBiquadFilter(), gain = ctx.createGain()
    noise.buffer = buffer
    filter.type = "highpass"
    filter.frequency.value = 6000
    gain.gain.value = level
    noise.connect(filter).connect(gain).connect(out)
    noise.start(at)
  }
}
