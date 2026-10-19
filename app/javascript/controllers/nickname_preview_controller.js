import { Controller } from "@hotwired/stimulus"
import { avatarColor } from "controllers/shared/avatar"

// Join form: the avatar disc fills in with the nickname's first letter, in the colour the player
// will have in the lobby, as they type. Empty, it's a dashed "?" circle.
const EMPTY = ["bg-slate-900", "border-dashed", "border-slate-600"]

export default class extends Controller {
  static targets = ["input", "disc"]

  connect() {
    this.update()
  }

  update() {
    const nickname = this.inputTarget.value.trim()
    const letter = nickname[0]?.toUpperCase() || "?"
    const disc = this.discTarget
    const color = nickname ? avatarColor(nickname) : null

    if (this.color) disc.classList.remove(this.color, "border-white")
    disc.classList.toggle("border-dashed", !color)
    if (color) {
      disc.classList.remove(...EMPTY)
      disc.classList.add(color, "border-white")
    } else {
      disc.classList.add(...EMPTY)
    }
    this.color = color

    if (disc.textContent !== letter && color && !window.matchMedia("(prefers-reduced-motion: reduce)").matches) {
      disc.classList.remove("animate-pop-in")
      void disc.offsetWidth // restart the animation
      disc.classList.add("animate-pop-in")
    }
    disc.textContent = letter
  }
}
