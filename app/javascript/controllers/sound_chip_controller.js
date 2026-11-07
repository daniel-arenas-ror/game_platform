import { Controller } from "@hotwired/stimulus"
import { soundOn, unlockSound, SOUND_BLOCKED, SOUND_CHANGE } from "controllers/shared/sound"

// "Tap for sound" (shared/_sound_chip): shows when a game asks for a sound the browser won't play
// yet, and hides once a tap anywhere turns the sound on.
export default class extends Controller {
  connect() {
    this.update = () => this.element.classList.toggle("hidden", soundOn())
    this.blocked = () => { if (!soundOn()) this.element.classList.remove("hidden") }
    window.addEventListener(SOUND_BLOCKED, this.blocked)
    window.addEventListener(SOUND_CHANGE, this.update)
  }

  disconnect() {
    window.removeEventListener(SOUND_BLOCKED, this.blocked)
    window.removeEventListener(SOUND_CHANGE, this.update)
  }

  turnOn() {
    unlockSound()
  }
}
