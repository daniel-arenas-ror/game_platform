import { Controller } from "@hotwired/stimulus"
import consumer from "channels/consumer"
import { t } from "controllers/shared/i18n"
import { confirmRemove, removePlayer } from "controllers/shared/remove_player"

// The shared "Players" panel (shared/_room_players) on the lobby and every game screen.
// Host: lists the room's players and removes the ones who aren't playing.
// Player: listens on RoomChannel and goes to the join page when the host removes them.
export default class extends Controller {
  static values  = { roomCode: String, playerId: String, playersUrl: String, removedUrl: String }
  static targets = ["dialog", "list", "count"]

  connect() {
    this.channel = consumer.subscriptions.create(
      { channel: "RoomChannel", room_code: this.roomCodeValue, player_id: this.playerIdValue },
      { received: (data) => this.received(data) }
    )
    if (this.isHost) this.refresh()
  }

  disconnect() {
    this.channel?.unsubscribe()
  }

  get isHost() {
    return this.hasDialogTarget
  }

  received(data) {
    if (data.action === "player_left" && data.player_id === this.playerIdValue) {
      window.location.href = this.removedUrlValue
      return
    }
    if (this.isHost && (data.action === "player_left" || data.action === "player_joined")) this.refresh()
  }

  open() {
    this.dialogTarget.showModal()
    this.refresh()
  }

  close() {
    this.dialogTarget.close()
  }

  // A click on the dimmed area around the panel lands on the <dialog> itself.
  backdropClose(event) {
    if (event.target === this.dialogTarget) this.close()
  }

  async refresh() {
    try {
      const response = await fetch(this.playersUrlValue, { headers: { Accept: "application/json" } })
      if (!response.ok) throw new Error(response.status)
      this.render(await response.json())
    } catch {
      this.listTarget.replaceChildren(this.message(t("room_players.error")))
    }
  }

  render(players) {
    this.countTarget.textContent = players.length || ""
    if (players.length === 0) {
      this.listTarget.replaceChildren(this.message(t("room_players.empty")))
      return
    }
    this.listTarget.replaceChildren(...players.map((player) => this.row(player)))
  }

  // Nicknames are typed by players: they go in as text, never as HTML.
  row(player) {
    const li = document.createElement("li")
    li.className = "flex items-center gap-3 rounded-xl border border-slate-700 bg-slate-800 px-3 py-2"

    const avatar = document.createElement("span")
    avatar.className = "flex h-9 w-9 shrink-0 items-center justify-center rounded-full bg-purple-500 font-bold"
    avatar.textContent = (player.nickname || "?")[0].toUpperCase()

    const name = document.createElement("span")
    name.className = "min-w-0 flex-1"
    const nick = document.createElement("span")
    nick.className = "block truncate font-bold"
    nick.textContent = player.nickname
    name.append(nick)
    if (!player.connected) {
      const offline = document.createElement("span")
      offline.className = "block text-xs text-amber-400"
      offline.textContent = t("room_players.offline")
      name.append(offline)
    }

    const remove = document.createElement("button")
    remove.type = "button"
    remove.className = "shrink-0 rounded-lg border border-red-500/40 bg-red-500/10 px-3 py-1.5 text-sm font-bold text-red-300 hover:bg-red-500/20 disabled:opacity-50 focus-visible:outline-2 focus-visible:outline-red-400"
    remove.textContent = t("room_players.remove")
    remove.setAttribute("aria-label", t("room_players.remove_player", { name: player.nickname }))
    remove.addEventListener("click", () => this.remove(player, remove))

    li.append(avatar, name, remove)
    return li
  }

  message(text) {
    const li = document.createElement("li")
    li.className = "py-6 text-center text-sm text-slate-500"
    li.textContent = text
    return li
  }

  async remove(player, button) {
    if (!confirmRemove(player)) return

    button.disabled = true
    button.textContent = t("room_players.removing")
    try {
      await removePlayer(this.playersUrlValue, player)
    } finally {
      this.refresh()
    }
  }
}
