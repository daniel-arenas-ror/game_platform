import { Controller } from "@hotwired/stimulus"

// Leans a card toward the pointer in 3D and springs back when the pointer leaves.
// Mouse and pen only (no tilt while scrolling on a phone), and off for reduced motion.
export default class extends Controller {
  static values = { max: { type: Number, default: 8 } } // degrees

  async connect() {
    if (!window.matchMedia("(hover: hover) and (prefers-reduced-motion: no-preference)").matches) return

    const { animate } = await import("motion")
    this.animate = animate
    this.onMove = this.move.bind(this)
    this.onLeave = this.leave.bind(this)
    this.element.addEventListener("pointermove", this.onMove)
    this.element.addEventListener("pointerleave", this.onLeave)
  }

  disconnect() {
    this.element.removeEventListener("pointermove", this.onMove)
    this.element.removeEventListener("pointerleave", this.onLeave)
  }

  move(event) {
    if (event.pointerType === "touch") return

    const box = this.element.getBoundingClientRect()
    const x = (event.clientX - box.left) / box.width - 0.5
    const y = (event.clientY - box.top) / box.height - 0.5
    this.animate(this.element, { transformPerspective: 800, rotateX: -y * this.maxValue, rotateY: x * this.maxValue, scale: 1.02 },
      { type: "spring", stiffness: 300, damping: 25 })
  }

  leave() {
    this.animate(this.element, { rotateX: 0, rotateY: 0, scale: 1 }, { type: "spring", stiffness: 200, damping: 18 })
  }
}
