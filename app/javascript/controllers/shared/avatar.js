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
  const svg = blobatar(String(nickname || "?"), { background: "circle" })
  return christmas() ? withSantaHat(svg) : svg
}

// Christmas mode (layouts/application puts data-christmas on <html>): every avatar wears the Santa
// hat from shared/_santa_hat, scaled to the avatar's 100×100 box. Its tip pokes out of the top.
const SANTA_HAT = `<g transform="translate(-4 -10) scale(0.2)"><g transform="rotate(10 290 130)">
  <path d="M130 118C160 20 250 -52 345 -54C420 -56 476 -8 492 52L446 72C434 44 414 30 398 34L428 118Z" fill="#dc2626"/>
  <path d="M345 -54C420 -56 476 -8 492 52L446 72C434 44 414 30 398 34C390 -4 372 -34 345 -54Z" fill="#b91c1c"/>
  <rect x="104" y="92" width="350" height="74" rx="37" fill="#fff"/>
  <circle cx="474" cy="70" r="40" fill="#fff"/>
</g></g>`

const christmas = () => document.documentElement.hasAttribute("data-christmas")

function withSantaHat(svg) {
  return svg.replace("<svg ", '<svg overflow="visible" ').replace(/<\/svg>\s*$/, `${SANTA_HAT}</svg>`)
}

export function avatarHtml(nickname, size = "size-10") {
  return `<span class="${size} shrink-0 inline-block rounded-full [&>svg]:size-full" aria-hidden="true">${avatarSvg(nickname)}</span>`
}

export function avatar(nickname, size = "size-10") {
  const template = document.createElement("template")
  template.innerHTML = avatarHtml(nickname, size)
  return template.content.firstElementChild
}
