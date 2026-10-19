import { Controller } from "@hotwired/stimulus"
import { t } from "controllers/shared/i18n"

// Catalog type filter: the pills show only the games of one category, and the cards that
// stay pop back in one after another. The pills are hidden without JS (every game shows).
export default class extends Controller {
  static targets = ["pills", "pill", "card", "status"]

  connect() {
    this.pillsTarget.hidden = false
  }

  async select(event) {
    const category = event.currentTarget.dataset.category
    this.pillTargets.forEach((pill) => pill.setAttribute("aria-pressed", pill === event.currentTarget))

    const shown = this.cardTargets.filter((card) => {
      const match = category === "all" || card.dataset.category === category
      card.hidden = !match
      return match
    })
    this.statusTarget.textContent = t("games.showing", { count: shown.length })

    if (window.matchMedia("(prefers-reduced-motion: reduce)").matches) return
    const { animate, stagger } = await import("motion")
    animate(shown, { opacity: [0, 1], scale: [0.92, 1], y: [12, 0] }, { delay: stagger(0.05), type: "spring", stiffness: 320, damping: 26 })
  }
}
