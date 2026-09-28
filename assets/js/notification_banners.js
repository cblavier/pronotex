export async function requestInbox(scope, tag) {
  const registration = await navigator.serviceWorker.getRegistration("/")
  const worker = registration?.active
  if (!worker) return {notifications: []}
  return new Promise((resolve, reject) => {
    const channel = new MessageChannel()
    const timer = setTimeout(() => {
      channel.port1.close()
      reject(new Error("inbox_timeout"))
    }, 5000)
    channel.port1.onmessage = ({data}) => {
      clearTimeout(timer)
      channel.port1.close()
      if (data.error) reject(new Error("inbox_unavailable"))
      else resolve(data)
    }
    worker.postMessage({type: tag ? "PUSH_INBOX_DISMISS" : "PUSH_INBOX_LIST", scope, tag}, [channel.port2])
  })
}

export const NotificationBanners = {
  mounted() {
    if (!("serviceWorker" in navigator)) return
    this.refreshInbox = async () => {
      try {
        const {notifications} = await requestInbox(this.el.dataset.scope)
        if (!this.stopped) this.pushEvent("received-notifications", {notifications})
      } catch { /* Preserve visible banners while offline storage is unavailable. */ }
    }
    this.onInboxMessage = event => {
      if (event.data?.type === "PUSH_INBOX_CHANGED") this.refreshInbox()
    }
    this.onInboxVisibility = () => {
      if (!document.hidden) this.refreshInbox()
    }
    this.onInboxClick = async event => {
      const action = event.target.closest("[data-notification-view], [data-notification-dismiss]")
      if (!action || !this.el.contains(action)) return
      event.preventDefault()
      const banner = action.closest("[data-notification-tag]")
      if (banner.dataset.pending) return
      banner.dataset.pending = "true"
      try {
        const {notifications} = await requestInbox(this.el.dataset.scope, banner.dataset.notificationTag)
        this.pushEvent("received-notifications", {notifications})
      } catch {
        delete banner.dataset.pending
        return
      }
      if (action.hasAttribute("data-notification-view")) window.location.assign(action.href)
    }
    navigator.serviceWorker.addEventListener("message", this.onInboxMessage)
    navigator.serviceWorker.addEventListener("controllerchange", this.refreshInbox)
    document.addEventListener("visibilitychange", this.onInboxVisibility)
    this.el.addEventListener("click", this.onInboxClick)
    this.refreshInbox()
  },
  reconnected() { this.refreshInbox?.() },
  destroyed() {
    this.stopped = true
    if (!this.refreshInbox) return
    navigator.serviceWorker.removeEventListener("message", this.onInboxMessage)
    navigator.serviceWorker.removeEventListener("controllerchange", this.refreshInbox)
    document.removeEventListener("visibilitychange", this.onInboxVisibility)
    this.el.removeEventListener("click", this.onInboxClick)
  }
}
