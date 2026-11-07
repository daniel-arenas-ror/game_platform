// The game's sounds: one note per colour (on the TV and on a phone's taps), a beep when the phones
// open and a short tune at game over.
import { Sounds } from "controllers/haunted_house/common"
import { soundOn } from "controllers/shared/sound"

const NOTES = { blue: 523.25, green: 659.25, yellow: 783.99, red: 880 }
const TAP_SECONDS = 0.6 // the same length as the TV's flash

export class ChainSounds extends Sounds {
  note(frequency, seconds, delay = 0, type = "triangle", volume = 0.4) {
    if (!this.ready) return
    const ctx = this.ctx, now = ctx.currentTime + delay
    const osc = ctx.createOscillator(), gain = ctx.createGain()
    osc.type = type
    osc.frequency.value = frequency
    gain.gain.setValueAtTime(0.0001, now)
    gain.gain.exponentialRampToValueAtTime(volume, now + 0.02)
    gain.gain.exponentialRampToValueAtTime(0.0001, now + seconds)
    osc.connect(gain).connect(this.master)
    osc.start(now); osc.stop(now + seconds + 0.02)
  }

  color(name, seconds) {
    this.note(NOTES[name], seconds)
  }

  // A phone's first tap is the one that turns the sound on, so its note waits for it to start.
  tap(name) {
    this.unlock()
    if (soundOn()) this.color(name, TAP_SECONDS)
    else this.ctx?.resume().then(() => this.color(name, TAP_SECONDS)).catch(() => {})
  }

  yourTurn() {
    this.note(987.77, 0.25, 0, "square", 0.12)
  }

  win() {
    [ NOTES.blue, NOTES.green, NOTES.yellow, 1046.5 ].forEach((frequency, i) => this.note(frequency, 0.35, i * 0.14))
  }
}
