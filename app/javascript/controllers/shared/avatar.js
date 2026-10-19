// Solid avatar discs for players, coloured from the nickname so a player keeps one colour on
// every screen. Same list and order as RoomsHelper::AVATAR_COLORS (Ruby renders the first rows).
//
//   import { avatar } from "controllers/shared/avatar"
//   row.append(avatar(player.nickname, "size-10 text-lg"))

const AVATAR_COLORS = [ "bg-purple-500", "bg-pink-500", "bg-sky-500", "bg-emerald-500", "bg-orange-500", "bg-violet-500", "bg-rose-500", "bg-cyan-600" ]

export function avatarColor(nickname) {
  const sum = [ ...String(nickname) ].reduce((total, ch) => total + ch.charCodeAt(0), 0)
  return AVATAR_COLORS[sum % AVATAR_COLORS.length]
}

// The disc with the nickname's first letter (set as text: nicknames are typed by players).
export function avatar(nickname, size = "size-10") {
  const disc = document.createElement("span")
  disc.className = `${size} shrink-0 rounded-full ${avatarColor(nickname)} font-display font-extrabold text-white flex items-center justify-center`
  disc.setAttribute("aria-hidden", "true")
  disc.textContent = (nickname || "?")[0].toUpperCase()
  return disc
}
