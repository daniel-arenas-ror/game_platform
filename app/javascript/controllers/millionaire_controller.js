import { Controller } from "@hotwired/stimulus"
import consumer from "channels/consumer"

export default class extends Controller {
  static targets = [
    "loading",
    "question",
    "input",
    "leaderboard",
    "questionText",
    "questionMeta",
    "optionA",
    "optionB",
    "optionC",
    "optionD"
  ]

  static values = { status: String, roomCode: String, playerId: String }

  connect() {
    console.log("HowWantBeBillionaireController connected")

    this.updateVisibility()
    this.subscribe()
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
    this.channel.perform('submit_millionaire_answer', { choice: selectedOption })
  }

  // Quick debug cycle method linked to the small buttons at the bottom
  debugState(event) {
    this.statusValue = event.currentTarget.dataset.state
  }

  subscribe() {
    console.log(`Subscribing to channel with roomCode: ${this.element.dataset.roomCode} and playerId: ${this.element.dataset.playerId === undefined}`)

    this.channel = consumer.subscriptions.create({
      channel: "Games::MillionaireChannel",
      room_code: this.element.dataset.roomCode,
      player_id: this.element.dataset.playerId
    }, {
      connected: () => {
        console.log("Connected to game channel!")

        if(this.statusValue === "loading" && this.element.dataset.playerId === '') {
          console.log("Starting game loop for host...")
          this.channel.perform('start_game_loop', {
            room_code: this.element.dataset.roomCode
          })
        }
      },
      received: (data) => {
        console.log("Received data on game channel:", data)

        switch (data.action) {
          case "send_question":
            console.log("Received question data:", data)
            this.statusValue = "loading"
            this.updateVisibility()

            this.questionMetaTarget.innerText = ``
            this.questionTextTarget.innerText = data.text
            
            this.optionATarget.innerText = data.options[0].text
            this.optionBTarget.innerText = data.options[1].text
            this.optionCTarget.innerText = data.options[2].text
            this.optionDTarget.innerText = data.options[3].text

            // 2. Clear out any button highlights from a previous round
            document.querySelectorAll('[data-action="click->millionaire#selectOption"]').forEach(btn => {
              btn.classList.remove("border-yellow-400")
              btn.classList.add("border-blue-800")
            })

            if (this.element.dataset.playerId === '') {
              this.statusValue = "question"
            } else {
              this.statusValue = "input"
            }

            this.updateVisibility()
            break;
          case "show_leaderboard":
            console.log("Received leaderboard data:", data.leaderboard)

            this.leaderboardTarget.innerHTML = Object.entries(data.leaderboard).map(([playerId, points]) => `
              <div class="flex justify-between">
                <span>Player ${playerId}</span>
                <span>${points} points</span>
              </div>
            `).join('')

            this.statusValue = "leaderboard"
            this.updateVisibility()
            break;
          case "player_presence":
            console.log("Player presence update:", data)
            break;
          default:
            console.warn(`Unhandled action: ${data.action}`, data);
        }
      }
    })
  }
}
