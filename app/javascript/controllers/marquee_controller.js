import { Controller } from "@hotwired/stimulus"

// Endless horizontal strip. The track's items are copied once (hidden from screen readers and
// out of the tab order), so the CSS animation moving the track by -50% loops seamlessly.
// Hovering or focusing pauses it; reduced motion leaves a plain scrollable row.
export default class extends Controller {
  static targets = ["track"]
  static values = { speed: { type: Number, default: 40 } } // pixels per second

  connect() {
    if (window.matchMedia("(prefers-reduced-motion: reduce)").matches) return

    const items = [...this.trackTarget.children]
    items.forEach((item) => {
      const copy = item.cloneNode(true)
      copy.setAttribute("aria-hidden", "true")
      copy.setAttribute("inert", "")
      copy.dataset.marqueeCopy = ""
      this.trackTarget.appendChild(copy)
    })

    const loopWidth = this.trackTarget.scrollWidth / 2
    this.trackTarget.style.setProperty("--marquee-duration", `${loopWidth / this.speedValue}s`)
    this.trackTarget.classList.add("is-looping")
  }

  disconnect() {
    this.trackTarget.querySelectorAll("[data-marquee-copy]").forEach((el) => el.remove())
    this.trackTarget.classList.remove("is-looping")
  }
}
