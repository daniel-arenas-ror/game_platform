import { Controller } from "@hotwired/stimulus"

// The home hero's lobby miniature plays the real flow on a loop: the phone types the room code,
// "You're in!" pops, and players drop into the TV's list one by one. The markup is the finished
// state, so without JS or with reduced motion it simply shows a full lobby. Runs only on screen.
export default class extends Controller {
  static targets = ["player", "slot", "joined"]

  async connect() {
    if (window.matchMedia("(prefers-reduced-motion: reduce)").matches) return

    const { animate, inView } = await import("motion")
    this.animate = animate
    this.stopInView = inView(this.element, () => {
      this.running = true
      this.loop()
      return () => { this.running = false }
    })
  }

  disconnect() {
    this.running = false
    this.stopInView?.()
  }

  async loop() {
    if (this.looping) return
    this.looping = true

    while (this.running && this.element.isConnected) {
      this.reset()
      await this.wait(500)

      for (const slot of this.slotTargets) {
        if (!this.running) break
        slot.textContent = slot.dataset.char
        slot.classList.replace("border-slate-600", "border-purple-400")
        this.animate(slot, { scale: [0.6, 1] }, { type: "spring", stiffness: 500, damping: 15 })
        await this.wait(260)
      }

      this.animate(this.joinedTarget, { opacity: [0, 1], scale: [0.5, 1] }, { type: "spring", stiffness: 400, damping: 14 })
      await this.wait(500)

      for (const player of this.playerTargets) {
        if (!this.running) break
        this.animate(player, { opacity: [0, 1], x: [-24, 0], scale: [0.9, 1] }, { type: "spring", stiffness: 380, damping: 22 })
        await this.wait(650)
      }

      await this.wait(2600)
      await this.animate([...this.playerTargets, this.joinedTarget], { opacity: 0 }, { duration: 0.3 }).finished
    }

    this.looping = false
  }

  reset() {
    this.playerTargets.forEach((el) => { el.style.opacity = 0 })
    this.joinedTarget.style.opacity = 0
    this.slotTargets.forEach((slot) => {
      slot.textContent = ""
      slot.classList.replace("border-purple-400", "border-slate-600")
    })
  }

  wait(ms) {
    return new Promise((resolve) => setTimeout(resolve, ms))
  }
}
