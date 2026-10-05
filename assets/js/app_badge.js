export async function applyAppBadge(count, target = navigator) {
  try {
    if (Number.isSafeInteger(count) && count > 0) await target.setAppBadge?.(count)
    if (count === 0) await target.clearAppBadge?.()
  } catch { /* Badging is optional and may be disabled by the device. */ }
}

export const AppBadge = {
  mounted() {
    if (!("setAppBadge" in navigator)) return
    this.syncBadge = () => {
      if (document.visibilityState === "hidden" || this.badgeDestroyed) return
      if (this.badgePending) { this.badgeAgain = true; return }
      this.badgePending = true
      fetch("/push/badge", {credentials: "same-origin", redirect: "error", cache: "no-store",
        headers: {Accept: "application/json"}})
        .then(response => response.ok ? response.json() : null)
        .then(state => {
          if (!this.badgeDestroyed && document.visibilityState !== "hidden") {
            return applyAppBadge(state?.count)
          }
        })
        .catch(() => { /* Preserve the badge offline or if the session has expired. */ })
        .finally(() => {
          this.badgePending = false
          if (this.badgeAgain) { this.badgeAgain = false; this.syncBadge() }
        })
    }
    this.badgeTimer = setInterval(this.syncBadge, 30_000)
    window.addEventListener("focus", this.syncBadge)
    document.addEventListener("visibilitychange", this.syncBadge)
    this.syncBadge()
  },
  updated() { this.syncBadge?.() },
  destroyed() {
    this.badgeDestroyed = true
    clearInterval(this.badgeTimer)
    if (this.syncBadge) {
      window.removeEventListener("focus", this.syncBadge)
      document.removeEventListener("visibilitychange", this.syncBadge)
    }
  }
}
