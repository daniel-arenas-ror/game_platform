import { Controller } from "@hotwired/stimulus"
import { avatarSvg } from "controllers/shared/avatar"

// Fills an avatar rendered by RoomsHelper#player_avatar with the player's blobatar.
export default class extends Controller {
  static values = { name: String }

  nameValueChanged() {
    this.element.innerHTML = avatarSvg(this.nameValue)
  }
}
