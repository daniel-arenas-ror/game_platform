import { Controller } from "@hotwired/stimulus"
import { t } from "controllers/shared/i18n"

// Join page: shows the room code as 4 slots over a real text input, and submits on the 4th character.
// Without JS the plain input still works.
export default class extends Controller {
  static targets = ["input", "slot", "submit"]
  static values = { length: { type: Number, default: 4 } }

  connect() {
    // Reset the button in case Turbo restored this page from its cache mid-submit.
    this.submitting = false
    this.submitTarget.disabled = false
    this.submitTarget.textContent = this.submitTarget.dataset.label
    this.element.dataset.enhanced = ""
    // autofocus can fire before this controller connects, so the focus action never ran.
    if (document.activeElement === this.inputTarget) this.element.dataset.focused = ""
    this.render()
    if (this.element.dataset.error !== undefined) this.inputTarget.select()
  }

  type() {
    delete this.element.dataset.error
    this.render()
    if (this.inputTarget.value.length === this.lengthValue) this.element.requestSubmit()
  }

  focus() {
    this.element.dataset.focused = ""
    this.render()
  }

  blur() {
    delete this.element.dataset.focused
    this.render()
  }

  submit(event) {
    if (this.submitting) return event.preventDefault()
    this.submitting = true
    this.submitTarget.disabled = true
    this.submitTarget.textContent = t("room_code.joining")
  }

  render() {
    const value = this.inputTarget.value.toUpperCase().replace(/[^A-Z0-9]/g, "").slice(0, this.lengthValue)
    if (this.inputTarget.value !== value) this.inputTarget.value = value

    const focused = this.element.dataset.focused !== undefined
    const active = Math.min(value.length, this.lengthValue - 1)
    this.slotTargets.forEach((slot, i) => {
      slot.textContent = value[i] || ""
      slot.dataset.state = focused && i === active ? "active" : (value[i] ? "filled" : "empty")
    })
  }
}
