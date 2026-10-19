import { Controller } from "@hotwired/stimulus"

// The hero's rotating word: every few seconds the word slides up and out, the next one slides in,
// and its solid colour block resizes and changes colour. The page shows the first word without JS
// or with reduced motion; the full list is in the heading as screen-reader text.
export default class extends Controller {
  static targets = ["word"]
  static values = { words: Array, colors: Array, interval: { type: Number, default: 2400 } }

  async connect() {
    if (this.wordsValue.length < 2) return
    if (window.matchMedia("(prefers-reduced-motion: reduce)").matches) return

    const { animate } = await import("motion")
    this.animate = animate
    this.index = 0
    this.timer = setInterval(() => this.next(), this.intervalValue)
  }

  disconnect() {
    clearInterval(this.timer)
  }

  async next() {
    if (document.hidden) return

    const previous = this.index
    this.index = (this.index + 1) % this.wordsValue.length
    const block = this.element
    const word = this.wordTarget
    const from = block.offsetWidth

    await this.animate(word, { y: "-110%", opacity: 0 }, { duration: 0.25, ease: "easeIn" }).finished
    if (!this.element.isConnected) return

    word.textContent = this.wordsValue[this.index]
    block.classList.replace(this.colorsValue[previous % this.colorsValue.length],
                            this.colorsValue[this.index % this.colorsValue.length])

    // Measure the new natural width, then grow or shrink the block to it from the old one
    block.style.width = ""
    const to = block.offsetWidth
    block.style.width = `${from}px`
    this.animate(block, { width: [`${from}px`, `${to}px`] }, { type: "spring", stiffness: 260, damping: 26 })
      .finished.then(() => { block.style.width = "" })
    this.animate(word, { y: ["110%", "0%"], opacity: [0, 1] }, { type: "spring", stiffness: 300, damping: 22 })
  }
}
