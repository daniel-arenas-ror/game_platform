import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["picker"]

  toggle() {
    this.pickerTarget.classList.toggle("hidden")
  }
}
