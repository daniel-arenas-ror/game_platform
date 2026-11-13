// The game's sounds: a ping for each new clue, ticks in the last seconds, right and wrong on the phone,
// a chime at the reveal and a short tune at game over.
import { Sounds } from "controllers/haunted_house/common"

export class WheelSounds extends Sounds {
  note(frequency, seconds, delay = 0, type = "triangle", volume = 0.35) {
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

  clue()   { this.note(880, 0.15); this.note(1318.5, 0.25, 0.12) }
  tick()   { this.note(1200, 0.06, 0, "square", 0.08) }
  reveal() { this.note(659.25, 0.3); this.note(987.77, 0.4, 0.15) }
  right()  { this.note(783.99, 0.15); this.note(1046.5, 0.3, 0.12) }
  wrong()  { this.note(196, 0.35, 0, "sawtooth", 0.18) }

  win() {
    [ 523.25, 659.25, 783.99, 1046.5 ].forEach((frequency, i) => this.note(frequency, 0.35, i * 0.14))
  }
}
