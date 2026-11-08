import { Controller } from "@hotwired/stimulus"
import { soundOn, unlockSound, SOUND_BLOCKED, SOUND_CHANGE } from "controllers/shared/sound"

const SHOW_MS = 8000 // a nudge, not a fixture: it can sit over a game's buttons (e.g. Play Again)

// "Tap for sound" (shared/_sound_chip): shows once per page when a game asks for a sound the
// browser won't play yet, and hides when a tap turns the sound on or after a few seconds.
export default class extends Controller {
  connect() {
    this.hide    = () => { clearTimeout(this.timer); this.element.classList.add("hidden") }
    this.update  = () => { if (soundOn()) this.hide() }
    this.blocked = () => {
      if (soundOn() || this.shown) return
      this.shown = true
      this.element.classList.remove("hidden")
      this.timer = setTimeout(this.hide, SHOW_MS)
    }
    window.addEventListener(SOUND_BLOCKED, this.blocked)
    window.addEventListener(SOUND_CHANGE, this.update)
  }

  disconnect() {
    clearTimeout(this.timer)
    window.removeEventListener(SOUND_BLOCKED, this.blocked)
    window.removeEventListener(SOUND_CHANGE, this.update)
  }

  turnOn() {
    unlockSound()
  }
}
