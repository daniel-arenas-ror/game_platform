import { Controller } from "@hotwired/stimulus"

// Asks AdSense to fill this <ins class="adsbygoogle"> unit. Runs on every Turbo page visit,
// which the plain inline snippet from Google would miss.
export default class extends Controller {
  connect() {
    if (this.element.dataset.adsbygoogleStatus) return // already filled (e.g. Turbo cache restore)

    try {
      (window.adsbygoogle = window.adsbygoogle || []).push({})
    } catch (_) { /* ad blocked or not ready */ }
  }
}
