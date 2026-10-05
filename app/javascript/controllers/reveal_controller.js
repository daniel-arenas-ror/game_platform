import { Controller } from "@hotwired/stimulus"

// Fades [data-reveal] children up as they scroll into view. Content stays visible without JS,
// and the CSS (application.css) skips the motion for prefers-reduced-motion.
export default class extends Controller {
  connect() {
    this.items = this.element.querySelectorAll("[data-reveal]")
    if (!("IntersectionObserver" in window)) return

    this.observer = new IntersectionObserver((entries) => {
      entries.forEach((entry) => {
        if (!entry.isIntersecting) return
        entry.target.classList.add("is-revealed")
        this.observer.unobserve(entry.target)
      })
    }, { rootMargin: "0px 0px -10% 0px" })

    this.element.classList.add("reveal-ready")
    this.items.forEach((el) => this.observer.observe(el))
  }

  disconnect() {
    this.observer?.disconnect()
  }
}
