// Push-only worker. Authenticated pages and API responses are never cached.
self.addEventListener("install", () => self.skipWaiting())
self.addEventListener("activate", event => event.waitUntil(self.clients.claim()))

self.addEventListener("push", event => {
  event.waitUntil((async () => {
    let payload = {}
    try { payload = event.data?.json() || {} } catch { /* Show a safe fallback. */ }
    let url = "/"
    try {
      const target = new URL(payload.url, self.location.origin)
      if (target.origin === self.location.origin) url = target.href
    } catch { /* Keep the app's home page. */ }
    await self.registration.showNotification(payload.title || "De nouvelles notes sont disponibles", {
      body: payload.body ?? "",
      icon: "/images/brand/captain-notes-skull-192.png",
      badge: "/images/brand/captain-notes-skull-192.png",
      tag: payload.tag,
      data: {url}
    })
  })())
})

self.addEventListener("notificationclick", event => {
  event.notification.close()
  event.waitUntil((async () => {
    const target = new URL(event.notification.data?.url || "/", self.location.origin)
    if (target.origin !== self.location.origin) return
    const windows = await self.clients.matchAll({type: "window", includeUncontrolled: true})
    for (const client of windows) {
      if (new URL(client.url).origin === target.origin && "navigate" in client) {
        // A running page can navigate itself even when iOS refuses Client.navigate.
        client.postMessage({type: "OPEN_NOTES", url: target.href})
        try {
          const navigated = await client.navigate(target.href)
          if (navigated) {
            // Focus failure must not cancel a successful navigation.
            try { await navigated.focus() } catch { /* Window may still be starting. */ }
            return
          }
        } catch { /* A suspended client may be unusable; try another window. */ }
      }
    }
    await self.clients.openWindow(target.href)
  })())
})
