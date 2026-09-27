const storageKey = account => `captain-last-page:${account}`
const maxAge = 60 * 60 * 1000
const isInstalled = () => window.matchMedia("(display-mode: standalone)").matches || window.navigator?.standalone === true

function savedPage(value) {
  try {
    const page = JSON.parse(value)
    const age = Date.now() - page.savedAt
    return Number.isFinite(page.savedAt) && age >= 0 && age < maxAge ? page : null
  } catch { return null }
}

export function appPath(value, origin) {
  if (typeof value !== "string" || value.length > 4096 || !value.startsWith("/") || value.startsWith("//")) return null
  try {
    const url = new URL(value, origin)
    const [, child, section, detail, ...extra] = url.pathname.split("/")
    if (url.origin !== origin || !child || extra.length) return null
    const name = decodeURIComponent(child)
    if (!/^[\p{L}\p{N}_-]+$/u.test(name) || ["login", "logout", "push", "avatars", "dev"].includes(name)) return null
    if (section !== undefined && !["agenda", "timetable", "devoirs", "notes", "reglages", "menu", "messages", "parent-messages"].includes(section)) return null
    if (detail !== undefined && (!detail || !["messages", "parent-messages"].includes(section))) return null
    return url.pathname + url.search + url.hash
  } catch { return null }
}

// Only restore the PWA's launch URL. Explicit links and notification destinations win.
// Run before LiveView connects so its default child redirect cannot overwrite the saved page.
export function restoreLastPage() {
  if (!isInstalled()) return false
  const account = document.querySelector("[data-page-account]")?.dataset.pageAccount
  if (!account || window.location.pathname !== "/" || window.location.search || window.location.hash) return false
  try {
    const key = storageKey(account)
    const saved = window.localStorage.getItem(key)
    const path = appPath(savedPage(saved)?.path, window.location.origin)
    if (!path) {
      if (saved) window.localStorage.removeItem(key)
      return false
    }
    window.location.replace(path)
    return true
  } catch { return false }
}

export const RememberPage = {
  mounted() {
    this.pageVisible = document.visibilityState !== "hidden"
    this.saveOnLeave = () => {
      if (this.pageVisible) this.rememberPage(true)
      this.pageVisible = false
    }
    this.onVisibility = () => {
      if (document.visibilityState === "hidden") this.saveOnLeave()
      else this.pageVisible = true
    }
    document.addEventListener("visibilitychange", this.onVisibility)
    window.addEventListener("pagehide", this.saveOnLeave)
    this.rememberPage()
  },
  updated() { this.rememberPage() },
  destroyed() {
    document.removeEventListener("visibilitychange", this.onVisibility)
    window.removeEventListener("pagehide", this.saveOnLeave)
  },
  rememberPage(leaving = false) {
    if (!isInstalled()) return
    if (!leaving && document.visibilityState === "hidden") return
    const {pageAccount, pageUrl, pageReady} = this.el.dataset
    if (!pageAccount || pageReady !== "true") return
    const path = appPath(pageUrl, window.location.origin)
    if (!path) return
    try { window.localStorage.setItem(storageKey(pageAccount), JSON.stringify({path, savedAt: Date.now()})) }
    catch { /* Browsing remains available when local storage is disabled or full. */ }
  }
}
