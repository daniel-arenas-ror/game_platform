// Escapes text before it goes into an HTML template string. Nicknames, guesses and answers are
// typed by players, so they must never be inserted as raw HTML.
//
//   import { escapeHtml } from "controllers/shared/html"
//   el.innerHTML = `<b>${escapeHtml(nickname)}</b>`
const ENTITIES = { "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" }

export function escapeHtml(value) {
  return String(value ?? "").replace(/[&<>"']/g, (ch) => ENTITIES[ch])
}
