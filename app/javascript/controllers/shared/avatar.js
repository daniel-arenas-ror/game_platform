// Player avatars: a blobatar (vendor/javascript/blobatar.js) made from the nickname, so a player
// keeps the same face on every screen, from the join form preview to the final leaderboard.
// Avatars drawn by ERB use avatar_controller.js (RoomsHelper#player_avatar).
//
//   import { avatar, avatarHtml } from "controllers/shared/avatar"
//   row.append(avatar(player.nickname, "size-10"))                    // DOM element
//   `<li>${avatarHtml(nickname, "size-8")} ${escapeHtml(nickname)}</li>`  // inside an HTML template

import { blobatar } from "blobatar"

// The SVG only holds shapes and colours (the nickname is hashed, never written into it), so it is
// safe in innerHTML even though nicknames are typed by players.
export function avatarSvg(nickname) {
  return blobatar(String(nickname || "?"), { background: "circle" })
}

export function avatarHtml(nickname, size = "size-10") {
  return `<span class="${size} shrink-0 inline-block rounded-full [&>svg]:size-full" aria-hidden="true">${avatarSvg(nickname)}</span>`
}

export function avatar(nickname, size = "size-10") {
  const template = document.createElement("template")
  template.innerHTML = avatarHtml(nickname, size)
  return template.content.firstElementChild
}
