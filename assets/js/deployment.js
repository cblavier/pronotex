// A restart changes this token even when only server code was deployed.
export function watchDeploymentVersion(socket) {
  const version = document.querySelector('meta[name="app-version"]')?.content
  if (!version) return
  let pending = false
  let reloading = false
  const check = async () => {
    if (pending || reloading || document.hidden) return
    pending = true
    try {
      const response = await fetch("/app-version", {cache: "no-store", credentials: "same-origin", redirect: "error"})
      if (!response.ok) return
      const current = await response.json()
      if (typeof current.version === "string" && current.version && current.version !== version) {
        reloading = true
        window.location.reload()
      }
    } catch { /* Offline or deploying: retry after reconnection or on the next check. */ }
    finally { pending = false }
  }
  socket.onOpen(check)
  document.addEventListener("visibilitychange", check)
  window.addEventListener("pageshow", check)
  window.addEventListener("online", check)
  // Also covers the login page and deployments without a socket interruption.
  window.setInterval(check, 60_000)
  check()
}
