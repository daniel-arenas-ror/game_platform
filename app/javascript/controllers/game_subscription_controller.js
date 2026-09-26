import { Controller } from "@hotwired/stimulus"
import consumer from "channels/consumer"

export default class extends Controller {
  static values = { roomCode: String, userId: String }

  connect() {
    this.subscribe()
  }

  disconnect() {
    if (this.channel) {
      this.channel.unsubscribe()
    }
  }

  subscribe() {
    console.log(`Subscribing to game channel for room: ${this.roomCodeValue}`)

    this.channel = consumer.subscriptions.create({
      channel: "GameChannel",
      room_code: this.roomCodeValue,
      player_id: this.userIdValue
    }, {
      connected: () => {
        console.log("Connected to game channel!")
      },
      // Our player was removed after being disconnected too long — send them back to join.
      rejected: () => {
        window.location.href = `/join/${this.roomCodeValue}`
      },
      received: (data) => {
        console.log("Received data on game channel:", data)

        switch (data.action) {
          case "game_started":
            window.location.reload();
            break;
          case "game_changed":
            window.location.reload();
            break;
          case "player_joined":
            const playerList = document.getElementById('player-list');
            if (!playerList) return;

            const newPlayer = `
              <div id="player-${data.player_id}" class="flex items-center space-x-4 bg-slate-700 p-4 rounded-xl border border-purple-500/30 animate-pulse">
                <div class="w-10 h-10 bg-gradient-to-br from-purple-500 to-pink-500 rounded-full flex items-center justify-center font-bold">
                  ${data.nickname[0].toUpperCase()}
                </div>
                <div class="text-white font-bold">${data.nickname}</div>
              </div>
            `;

            playerList.insertAdjacentHTML('afterbegin', newPlayer);
            break;
          case "player_left":
            document.getElementById(`player-${data.player_id}`)?.remove();
            break;
          default:
            console.warn(`Unhandled action: ${data.action}`, data);
        }
      }
    })
  }
}
