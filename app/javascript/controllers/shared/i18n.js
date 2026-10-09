// Translations for the Stimulus controllers. The layout embeds the current language's `js:`
// strings from config/locales (LocaleHelper#js_translations_tag); inside a room that is the
// room's language.
//
//   import { t } from "controllers/shared/i18n"
//   t("mind_match.waiting", { count: 3 })   // "Waiting for %{count} players" → "Waiting for 3 players"
//
// Keys may be nested with dots. A missing key returns the key itself, so it's easy to spot.
let strings = null

function load() {
  if (strings) return strings
  try {
    strings = JSON.parse(document.getElementById("i18n-strings")?.textContent || "{}")
  } catch {
    strings = {}
  }
  return strings
}

export const locale = () => document.documentElement.lang || "en"

export function t(key, vars = {}) {
  let value = key.split(".").reduce((node, part) => (node == null ? undefined : node[part]), load())
  // Rails-style plurals: { one: "...", other: "..." } picked by vars.count.
  if (value && typeof value === "object" && "count" in vars) {
    value = vars.count === 1 && value.one !== undefined ? value.one : (value.other ?? value.one)
  }
  if (typeof value !== "string") return key
  return value.replace(/%\{(\w+)\}/g, (match, name) => (name in vars ? String(vars[name]) : match))
}
