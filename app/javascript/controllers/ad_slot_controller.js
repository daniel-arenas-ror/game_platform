import { Controller } from "@hotwired/stimulus"

const SCRIPT_SRC = "https://pagead2.googlesyndication.com/pagead/js/adsbygoogle.js"

// Fills this <ins class="adsbygoogle"> unit. Works on every Turbo page visit (which Google's
// inline snippet would miss) and waits until the unit is actually on screen: game-over ads sit
// in a hidden overlay, and AdSense can't size a unit while it is display:none. Game pages don't
// load the AdSense script up front, so it is added here the first time an ad needs it.
export default class extends Controller {
  connect() {
    if (this.element.dataset.adsbygoogleStatus) return // already filled (e.g. Turbo cache restore)

    this.observer = new IntersectionObserver((entries) => {
      if (!entries.some(e => e.isIntersecting)) return
      this.observer.disconnect()
      this.fill()
    })
    this.observer.observe(this.element)
  }

  disconnect() {
    this.observer?.disconnect()
  }

  fill() {
    this.loadScript()
    try {
      (window.adsbygoogle = window.adsbygoogle || []).push({})
    } catch (_) { /* ad blocked or not ready */ }
  }

  loadScript() {
    if (document.querySelector(`script[src^="${SCRIPT_SRC}"]`)) return

    const script = document.createElement("script")
    script.async       = true
    script.crossOrigin = "anonymous"
    script.src         = `${SCRIPT_SRC}?client=${this.element.dataset.adClient}`
    document.head.appendChild(script)
  }
}
