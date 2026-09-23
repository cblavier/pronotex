export function pushSupported() {
  const ios = /iPad|iPhone|iPod/.test(navigator.userAgent) || (navigator.platform === "MacIntel" && navigator.maxTouchPoints > 1)
  const installed = matchMedia("(display-mode: standalone)").matches || navigator.standalone === true
  return window.isSecureContext && "Notification" in window && "serviceWorker" in navigator && "PushManager" in window && (!ios || installed)
}

async function request(path, method = "GET", body) {
  const csrf = document.querySelector('meta[name="csrf-token"]').content
  const response = await fetch(path, {
    method, credentials: "same-origin", redirect: "error",
    headers: {"Accept": "application/json", "Content-Type": "application/json", "x-csrf-token": csrf},
    body: body ? JSON.stringify(body) : undefined
  })
  if (!response.ok) throw new Error("push_request_failed")
  return response.json()
}

export async function pushState() {
  const config = await request("/push/config")
  const registration = await navigator.serviceWorker.getRegistration("/")
  const subscription = registration && await registration.pushManager.getSubscription()
  return {enabled: config.enabled && !!subscription && Notification.permission === "granted", publicKey: config.publicKey}
}

export async function enablePush(publicKey) {
  // Called from a click handler before any network/registration await (required on iOS).
  const permission = Notification.permission === "default" ? await Notification.requestPermission() : Notification.permission
  if (permission !== "granted") return false
  const registration = await navigator.serviceWorker.register("/push-sw.js", {scope: "/", updateViaCache: "none"})
  await navigator.serviceWorker.ready
  const bytes = Uint8Array.from(atob(publicKey.replace(/-/g, "+").replace(/_/g, "/")), c => c.charCodeAt(0))
  let subscription = await registration.pushManager.getSubscription()
  if (subscription?.options.applicationServerKey) {
    const previous = new Uint8Array(subscription.options.applicationServerKey)
    if (previous.length !== bytes.length || previous.some((v, i) => v !== bytes[i])) {
      await subscription.unsubscribe()
      subscription = null
    }
  }
  subscription ||= await registration.pushManager.subscribe({userVisibleOnly: true, applicationServerKey: bytes})
  await request("/push/subscription", "POST", subscription.toJSON())
  return true
}

export async function disablePush() {
  // Remove the server subscription first. A failed request must not report success.
  await request("/push/subscription", "DELETE")
  const registration = await navigator.serviceWorker.getRegistration("/")
  const subscription = registration && await registration.pushManager.getSubscription()
  if (subscription) await subscription.unsubscribe()
}

// Refresh an existing installation on each app load, without requesting permission.
export async function updatePushWorker() {
  if (!("serviceWorker" in navigator)) return
  try {
    const registration = await navigator.serviceWorker.getRegistration("/")
    if (registration) await registration.update()
  } catch { /* Offline: keep the installed worker until the next app load. */ }
}

export function listenForPushNavigation() {
  if (!("serviceWorker" in navigator)) return
  navigator.serviceWorker.addEventListener("message", event => {
    if (event.data?.type !== "OPEN_NOTES") return
    try {
      const target = new URL(event.data.url, window.location.origin)
      if (target.origin === window.location.origin && /^\/[^/]+\/notes$/.test(target.pathname)) {
        window.location.assign(target.href)
      }
    } catch { /* Ignore malformed notification destinations. */ }
  })
}
