import { Controller } from "@hotwired/stimulus"

// A pretend live leaderboard on the home page: every couple of seconds someone scores, a gold
// "+points" pops beside them and the rows spring into their new order. With JS the rows are
// placed by rank (absolute, one row height apart); without it they are a plain ordered list.
const ROW_HEIGHT = 64 // px; keep in step with the rows' h-14 + gap in home/_leaderboard_demo

export default class extends Controller {
  static targets = ["list", "row"]

  async connect() {
    this.rows = this.rowTargets.map((el) => ({ el, score: Number(el.dataset.score) }))
    this.listTarget.style.position = "relative"
    this.listTarget.style.height = `${this.rows.length * ROW_HEIGHT - (ROW_HEIGHT - 56)}px`
    this.rowTargets.forEach((el) => Object.assign(el.style, { position: "absolute", top: 0, left: 0, right: 0 }))
    this.place(false)
    if (window.matchMedia("(prefers-reduced-motion: reduce)").matches) return

    const { animate, inView } = await import("motion")
    this.animate = animate
    this.stopInView = inView(this.element, () => {
      this.timer = setInterval(() => this.score(), 2000)
      return () => clearInterval(this.timer)
    })
  }

  disconnect() {
    clearInterval(this.timer)
    this.stopInView?.()
  }

  score() {
    if (document.hidden) return

    // Players further down score more often, so the order keeps changing
    const ranked = this.ranked()
    const pick = ranked[Math.min(ranked.length - 1, Math.floor(Math.random() ** 0.6 * ranked.length))]
    const points = [50, 100, 150, 200][Math.floor(Math.random() * 4)]
    const from = pick.score
    pick.score += points

    const scoreEl = pick.el.querySelector("[data-score-value]")
    this.animate(from, pick.score, { duration: 0.6, onUpdate: (v) => { scoreEl.textContent = Math.round(v) } })

    const bump = pick.el.querySelector("[data-bump]")
    bump.textContent = `+${points}`
    this.animate(bump, { opacity: [0, 1, 1, 0], y: [8, -4, -4, -16], scale: [0.6, 1.15, 1, 1] }, { duration: 1.1, times: [0, 0.2, 0.7, 1] })

    this.place(true)
  }

  ranked() {
    return [...this.rows].sort((a, b) => b.score - a.score)
  }

  place(animated) {
    this.ranked().forEach((row, rank) => {
      row.el.toggleAttribute("data-leader", rank === 0)
      const y = rank * ROW_HEIGHT
      if (animated) {
        this.animate(row.el, { y }, { type: "spring", stiffness: 260, damping: 24 })
      } else {
        row.el.style.transform = `translateY(${y}px)`
      }
    })
  }
}
