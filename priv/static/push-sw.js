// Only received push payloads are stored here; no pages or API responses.
const inboxCache = "received-push-v1"
const inboxKey = (scope, tag) => new URL("/__push-inbox/" + encodeURIComponent(scope) + "/" + encodeURIComponent(tag), self.location.origin).href

async function notifyInboxChanged() {
  const windows = await self.clients.matchAll({type: "window", includeUncontrolled: true})
  for (const client of windows) client.postMessage({type: "PUSH_INBOX_CHANGED"})
}

async function saveReceivedPush(payload) {
  if (!payload.scope || !payload.tag || !["grades", "cancellation"].includes(payload.kind)) return
  const url = new URL(payload.url, self.location.origin)
  if (url.origin !== self.location.origin) return
  const cache = await caches.open(inboxCache)
  await cache.put(inboxKey(payload.scope, payload.tag), new Response(JSON.stringify({
    scope: payload.scope, tag: payload.tag, kind: payload.kind,
    url: url.pathname + url.search, receivedAt: Date.now()
  }), {headers: {"Content-Type": "application/json"}}))
  await notifyInboxChanged()
}

async function dismissReceivedPush(scope, tag) {
  if (!scope || !tag) return
  const cache = await caches.open(inboxCache)
  await cache.delete(inboxKey(scope, tag))
  const notifications = await self.registration.getNotifications()
  for (const notification of notifications) {
    if (notification.data?.scope === scope && notification.data?.tag === tag) notification.close()
  }
  await notifyInboxChanged()
}

self.addEventListener("message", event => {
  const {type, scope, tag} = event.data || {}
  if (!event.source?.url || new URL(event.source.url).origin !== self.location.origin ||
      typeof scope !== "string" || !["PUSH_INBOX_LIST", "PUSH_INBOX_DISMISS"].includes(type)) return
  event.waitUntil((async () => {
    try {
      if (type === "PUSH_INBOX_DISMISS" && typeof tag === "string") await dismissReceivedPush(scope, tag)
      const cache = await caches.open(inboxCache)
      const entries = await Promise.all((await cache.matchAll()).map(response => response.json()))
      const notifications = entries.filter(entry => entry.scope === scope).sort((a, b) => a.receivedAt - b.receivedAt)
      event.ports[0]?.postMessage({notifications})
    } catch {
      event.ports[0]?.postMessage({error: true})
    }
  })())
})

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
    try { await saveReceivedPush(payload) } catch { /* Storage must not block system notifications. */ }
    await self.registration.showNotification(payload.title || "Nouvelle notes", {
      body: payload.body ?? "",
      icon: "/images/brand/captain-notes-skull-192.png",
      badge: "/images/brand/captain-notes-skull-192.png",
      tag: payload.tag,
      data: {url, scope: payload.scope, tag: payload.tag}
    })
  })())
})

self.addEventListener("notificationclick", event => {
  event.notification.close()
  event.waitUntil((async () => {
    try {
      await dismissReceivedPush(event.notification.data?.scope, event.notification.data?.tag)
    } catch { /* Navigation remains available when storage is unavailable. */ }
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
