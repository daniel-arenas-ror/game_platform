import { Controller } from "@hotwired/stimulus"

// Fades [data-reveal] children up as they scroll into view. Content stays visible without JS,
// and the CSS (application.css) skips the motion for prefers-reduced-motion.
// Children of a [data-reveal-stagger="80"] group come in one after another, 80ms apart; in a
// grid, data-reveal-stagger-cols="3" restarts the count on each row.
export default class extends Controller {
  connect() {
    this.items = this.element.querySelectorAll("[data-reveal]")
    if (!("IntersectionObserver" in window)) return

    this.element.querySelectorAll("[data-reveal-stagger]").forEach((group) => {
      const step = Number(group.dataset.revealStagger) || 80
      const cols = Number(group.dataset.revealStaggerCols) || Infinity
      group.querySelectorAll("[data-reveal]").forEach((el, i) => {
        el.style.setProperty("--reveal-delay", `${(i % cols) * step}ms`)
      })
    })

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
