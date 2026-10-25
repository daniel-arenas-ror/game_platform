import { Controller } from "@hotwired/stimulus"
import { avatarSvg } from "controllers/shared/avatar"

// Join form: the avatar fills in with the player's blobatar (the face they'll have in the lobby and
// on the leaderboards) as they type. Empty, it's a dashed "?" circle.
const EMPTY = ["bg-slate-900", "border-dashed", "border-slate-600"]

export default class extends Controller {
  static targets = ["input", "disc"]

  connect() {
    this.update()
  }

  update() {
    const nickname = this.inputTarget.value.trim()
    const disc = this.discTarget
    if (nickname === this.nickname) return

    disc.classList.toggle("border-white", !!nickname)
    EMPTY.forEach(cls => disc.classList.toggle(cls, !nickname))
    disc.innerHTML = nickname ? avatarSvg(nickname) : "?"

    if (nickname && !this.nickname && !window.matchMedia("(prefers-reduced-motion: reduce)").matches) {
      disc.classList.remove("animate-pop-in")
      void disc.offsetWidth // restart the animation
      disc.classList.add("animate-pop-in")
    }
    this.nickname = nickname
  }
}
