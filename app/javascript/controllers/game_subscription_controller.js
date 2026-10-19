import { Controller } from "@hotwired/stimulus"
import consumer from "channels/consumer"
import { t } from "controllers/shared/i18n"
import { confirmRemove, removePlayer } from "controllers/shared/remove_player"
import { avatar } from "controllers/shared/avatar"

const REMOVE_CLASS = "shrink-0 rounded-lg border border-red-500/40 bg-red-500/10 px-3 py-1.5 text-sm font-bold text-red-300 hover:bg-red-500/20 disabled:opacity-50 focus-visible:outline-2 focus-visible:outline-red-400"

export default class extends Controller {
  static values = { roomCode: String, userId: String, host: Boolean, playersUrl: String }

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
            this.addPlayer(data)
            break;
          case "player_left":
            document.getElementById(`player-${data.player_id}`)?.remove();
            this.updateCount()
            break;
          default:
            console.warn(`Unhandled action: ${data.action}`, data);
        }
      }
    })
  }

  // Same row as rooms/_lobby_player; it pops in at the top of the list.
  // Nicknames are typed by players, so they go in as text, never as HTML.
  addPlayer(data) {
    const playerList = document.getElementById("player-list")
    if (!playerList || document.getElementById(`player-${data.player_id}`)) return

    const row = document.createElement("div")
    row.id = `player-${data.player_id}`
    row.className = "flex items-center gap-3 rounded-2xl border-2 border-purple-400 bg-slate-900 p-3 motion-safe:animate-pop-in transition-colors duration-1000"

    const name = document.createElement("span")
    name.className = "flex-1 min-w-0 truncate font-bold text-white"
    name.textContent = data.nickname

    row.append(avatar(data.nickname, "size-10 text-lg"), name)
    if (this.hostValue) row.append(this.removeButton(data))
    playerList.prepend(row)
    // Lit purple as it arrives, then settles like the others
    setTimeout(() => row.classList.replace("border-purple-400", "border-slate-700"), 1200)
    this.updateCount()
  }

  updateCount() {
    const count = document.querySelectorAll("#player-list > [id^='player-']").length
    const badge = document.getElementById("player-count")
    if (badge) badge.textContent = t("room_players.players_count", { count })
  }

  removeButton(data) {
    const button = document.createElement("button")
    button.type = "button"
    button.className = REMOVE_CLASS
    button.dataset.action = "game-subscription#remove"
    button.dataset.playerId = data.player_id
    button.dataset.nickname = data.nickname
    button.setAttribute("aria-label", t("room_players.remove_player", { name: data.nickname }))
    button.textContent = t("room_players.remove")
    return button
  }

  // Host only. The row goes away when the "player_left" broadcast arrives.
  async remove(event) {
    const button = event.currentTarget
    const player = { id: button.dataset.playerId, nickname: button.dataset.nickname }
    if (!confirmRemove(player)) return

    button.disabled = true
    button.textContent = t("room_players.removing")
    try {
      const response = await removePlayer(this.playersUrlValue, player)
      if (!response.ok) throw new Error(response.status)
    } catch {
      button.disabled = false
      button.textContent = t("room_players.remove")
    }
  }
}
