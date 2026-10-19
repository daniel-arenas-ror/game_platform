import { Controller } from "@hotwired/stimulus"

// "How it works" on wide screens: the picture stays pinned while the steps scroll past, and it
// switches when a step's text crosses the middle of the screen (and keeps the last one between
// steps). Sets data-active="N" on the element;
// the CSS shows the matching [data-step-visual]. Phones show each step's picture inline instead.
export default class extends Controller {
  static targets = ["step"]

  connect() {
    if (!("IntersectionObserver" in window)) return

    this.observer = new IntersectionObserver((entries) => {
      entries.forEach((entry) => {
        if (entry.isIntersecting) this.element.dataset.active = entry.target.dataset.step
      })
    }, { rootMargin: "-40% 0px -40% 0px" })

    this.stepTargets.forEach((el) => this.observer.observe(el))
  }

  disconnect() {
    this.observer?.disconnect()
  }
}
