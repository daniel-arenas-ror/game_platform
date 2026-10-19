import { Controller } from "@hotwired/stimulus"

// The sticky site header gets a solid backdrop and a bottom rule once the page has scrolled.
export default class extends Controller {
  connect() {
    this.onScroll = () => this.element.toggleAttribute("data-scrolled", window.scrollY > 8)
    this.onScroll()
    window.addEventListener("scroll", this.onScroll, { passive: true })
  }

  disconnect() {
    window.removeEventListener("scroll", this.onScroll)
  }
}
