import { Controller } from "@hotwired/stimulus"
import consumer from "channels/consumer"

export default class extends Controller {
static targets = ["loading", "question", "input", "leaderboard"]
  static values = { status: String }

  connect() {
    console.log("HowWantBeBillionaireController connected")
    this.updateVisibility()
  }

  disconnect() {
    console.log("disconneted!!!")
  }

  // Automatically fires whenever data-millionaire-status-value changes
  statusValueChanged() {
    this.updateVisibility()
  }

  updateVisibility() {
    const currentStatus = this.statusValue

    // Hide everything first
    this.loadingTarget.classList.add("hidden")
    this.questionTarget.classList.add("hidden")
    this.inputTarget.classList.add("hidden")
    this.leaderboardTarget.classList.add("hidden")

    // Show the active target match
    if (currentStatus === "loading")       this.loadingTarget.classList.remove("hidden")
    if (currentStatus === "question")      this.questionTarget.classList.remove("hidden")
    if (currentStatus === "input")         this.inputTarget.classList.remove("hidden")
    if (currentStatus === "leaderboard")   this.leaderboardTarget.classList.remove("hidden")
  }

  // Handles checking an interactive answer selection from Section 3
  selectOption(event) {
    const selectedOption = event.currentTarget.dataset.option
    
    // Highlight effect on selected choice
    document.querySelectorAll('[data-action="click->millionaire#selectOption"]').forEach(btn => {
      btn.classList.replace("border-yellow-400", "border-blue-800")
    })
    event.currentTarget.classList.replace("border-blue-800", "border-yellow-400")

    console.log(`Player selected option: ${selectedOption}`)
    
    // Here you would execute ActionCable payload transmissions:
    // this.channel.perform('submit_millionaire_answer', { choice: selectedOption })
  }

  // Quick debug cycle method linked to the small buttons at the bottom
  debugState(event) {
    this.statusValue = event.currentTarget.dataset.state
  }
}
