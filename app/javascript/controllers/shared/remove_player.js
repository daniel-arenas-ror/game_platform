import { t } from "controllers/shared/i18n"

// Host only: removing a player from the room (RoomsController#remove_player). Used by the
// Players panel and the lobby list.
//
//   import { confirmRemove, removePlayer } from "controllers/shared/remove_player"
//   if (confirmRemove(player)) await removePlayer(playersUrl, player)   // player: { id, nickname }
export function confirmRemove(player) {
  return window.confirm(t("room_players.confirm", { name: player.nickname }))
}

export function removePlayer(playersUrl, player) {
  const token = document.querySelector("meta[name='csrf-token']")?.content
  return fetch(`${playersUrl}/${encodeURIComponent(player.id)}`, {
    method: "DELETE",
    headers: { "X-CSRF-Token": token, Accept: "application/json" }
  })
}
