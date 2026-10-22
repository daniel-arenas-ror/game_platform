// Google Analytics custom events. gtag only exists in production with a measurement ID
// (AnalyticsHelper), so everywhere else this does nothing.
export function track(name, params = {}) {
  window.gtag?.("event", name, params)
}
