import {watchDeploymentVersion} from "./deployment"
import {AppBadge, applyAppBadge} from "./app_badge"
import {MessageComposer} from "./message_composer"
import {WeekOverview} from "./week_overview"
import {updatePushWorker, listenForPushNavigation} from "./push"
// Establish Phoenix Socket and LiveView configuration.
import {Socket} from "phoenix"
import {startFooterCat, footerCatActive} from "./footer_cat"
import {LiveSocket} from "phoenix_live_view"
import {Settings} from "./settings"

// The login form is a regular POST form, outside LiveView.
document.addEventListener("click", event => {
  const key = event.target.closest("#pin-form [data-pin-digit], #pin-form [data-pin-action]")
  if (!key) return
  const input = document.querySelector("#pin-form #pin")
  if (!input) return
  if (key.dataset.pinAction === "clear") input.value = ""
  else if (key.dataset.pinAction === "backspace") input.value = input.value.slice(0, -1)
  else input.value = input.value + key.dataset.pinDigit
  input.dispatchEvent(new Event("input", {bubbles: true}))
})

// Native events also work on the login form, which lives outside LiveView.
document.addEventListener("change", event => {
  const picker = event.target.closest("[data-dropdown]")
  if (!picker || !event.target.matches('input[type="radio"]')) return
  picker.querySelector("[data-dropdown-label]").textContent =
    event.target.closest("label").querySelector("[data-option-label]").textContent
  picker.open = false
  picker.querySelector("summary").focus()
  if (picker.id === "login-account-picker") {
    const pin = document.querySelector("#pin-form #pin")
    if (pin) pin.value = ""
  }
})
document.addEventListener("click", event => {
  document.querySelectorAll("[data-dropdown][open]").forEach(picker => {
    if (!picker.contains(event.target)) picker.open = false
  })
})
document.addEventListener("keydown", event => {
  if (event.key !== "Escape") return
  document.querySelectorAll("[data-dropdown][open]").forEach(picker => {
    picker.open = false
    picker.querySelector("summary").focus()
  })
})

const csrfToken = document.querySelector("meta[name='csrf-token']").getAttribute("content")
const AgendaScroll = {
  mounted() {
    this.savedAgendaScroll = null
    this.saveAgendaScroll = event => {
      if (!event.target.closest(".lesson-detail-link")) return
      this.savedAgendaScroll = {
        key: this.el.dataset.agendaKey,
        x: window.scrollX,
        y: window.scrollY
      }
    }
    this.el.addEventListener("click", this.saveAgendaScroll, true)
  },
  updated() {
    const saved = this.savedAgendaScroll
    if (!saved) return
    if (saved.key !== this.el.dataset.agendaKey) {
      this.savedAgendaScroll = null
      return
    }
    const agenda = this.el.querySelector("#agenda-content")
    if (this.el.hidden || !agenda || agenda.hidden) return
    this.savedAgendaScroll = null
    // Wait for the restored agenda and LiveView's navigation scroll to settle.
    this.scrollFrame = requestAnimationFrame(() => {
      this.scrollFrame = requestAnimationFrame(() => {
        if (this.el.isConnected && !agenda.hidden && this.el.dataset.agendaKey === saved.key) {
          window.scrollTo({left: saved.x, top: saved.y, behavior: "instant"})
        }
      })
    })
  },
  destroyed() {
    cancelAnimationFrame(this.scrollFrame)
    this.el.removeEventListener("click", this.saveAgendaScroll, true)
  }
}
const liveSocket = new LiveSocket("/live", Socket, {
  longPollFallbackMs: 2500,
  params: {_csrf_token: csrfToken},
  hooks: {MessageComposer, WeekOverview, AgendaScroll, Settings, AppBadge},
})

// Give reconnects a grace period, including after returning to a sleeping tab.
const pendingConnectionAlerts = new Map()
const hideConnectionAlert = element => {
  clearTimeout(pendingConnectionAlerts.get(element))
  element.hidden = true
  element.style.display = "none"
}
const scheduleConnectionAlert = element => {
  hideConnectionAlert(element)
  pendingConnectionAlerts.set(element, null)
  if (document.hidden) return
  pendingConnectionAlerts.set(element, setTimeout(() => {
    if (element.isConnected && !document.hidden) {
      element.hidden = false
      element.style.display = "block"
    }
  }, 5000))
}
window.addEventListener("connection-alert:pending", event => {
  if (!pendingConnectionAlerts.has(event.target)) scheduleConnectionAlert(event.target)
})
window.addEventListener("connection-alert:clear", event => {
  hideConnectionAlert(event.target)
  pendingConnectionAlerts.delete(event.target)
})
document.addEventListener("visibilitychange", () => {
  for (const element of pendingConnectionAlerts.keys()) {
    if (element.isConnected) scheduleConnectionAlert(element)
    else {
      hideConnectionAlert(element)
      pendingConnectionAlerts.delete(element)
    }
  }
})

watchDeploymentVersion(liveSocket.socket)

// connect if there are any LiveViews on the page
liveSocket.connect()

// A temporary overlay keeps the celebration independent of LiveView patches.
const captainConfetti = () => {
  document.querySelector(".captain-confetti")?.remove()
  const overlay = document.createElement("div")
  overlay.className = "captain-confetti"
  overlay.setAttribute("aria-hidden", "true")
  const colors = ["#fbbf24", "#fb7185", "#38bdf8", "#a78bfa", "#34d399", "#f97316"]
  const particles = Array.from({length: 120}, () => {
    const piece = document.createElement("span")
    piece.style.left = `${Math.random() * 100}%`
    piece.style.backgroundColor = colors[Math.floor(Math.random() * colors.length)]
    piece.style.width = `${5 + Math.random() * 5}px`
    piece.style.height = `${7 + Math.random() * 7}px`
    overlay.appendChild(piece)
    return piece
  })
  document.body.appendChild(overlay)
  const animations = particles.map(piece => {
    const drift = Math.random() * 240 - 120
    const spin = Math.random() * 1080 - 540
    return piece.animate([
      {transform: "translate3d(0, -20px, 0) rotate(0deg)", opacity: 1},
      {transform: `translate3d(${drift * 0.8}px, 80dvh, 0) rotate(${spin * 0.8}deg)`, opacity: 1, offset: 0.8},
      {transform: `translate3d(${drift}px, calc(100dvh + 20px), 0) rotate(${spin}deg)`, opacity: 0}
    ], {duration: 2200 + Math.random() * 1000, delay: Math.random() * 600, easing: "linear", fill: "both"})
  })
  Promise.allSettled(animations.map(animation => animation.finished)).then(() => overlay.remove())
}

let captainMirrorTimer
const captainMirror = () => {
  window.clearTimeout(captainMirrorTimer)
  document.body.classList.add("captain-mirror")
  captainMirrorTimer = window.setTimeout(() => {
    document.body.classList.remove("captain-mirror")
  }, 1 * 60 * 1000)
}

let cleanupCaptainPalette
const captainPalette = className => {
  if (["captain-pink", "captain-brown"].some(name =>
    name !== className && document.body.classList.contains(name)
  )) return
  cleanupCaptainPalette?.()
  const themeColor = document.querySelector('meta[name="theme-color"]')
  const previousThemeColor = themeColor?.getAttribute("content")
  document.body.classList.add(className)
  const syncThemeColor = () => {
    themeColor?.setAttribute("content", getComputedStyle(document.body).getPropertyValue("--page-background").trim())
  }
  syncThemeColor()
  const themeObserver = new MutationObserver(syncThemeColor)
  themeObserver.observe(document.documentElement, {attributes: true, attributeFilter: ["data-theme"]})
  const cleanup = () => {
    themeObserver.disconnect()
    document.body.classList.remove(className)
    if (previousThemeColor == null) themeColor?.removeAttribute("content")
    else themeColor?.setAttribute("content", previousThemeColor)
    window.clearTimeout(timer)
  }
  cleanupCaptainPalette = cleanup
  const timer = window.setTimeout(cleanup, 1 * 60 * 1000)
}
const captainPink = () => captainPalette("captain-pink")
const captainBrown = () => captainPalette("captain-brown")

// Short surprises from the captain, including keyboard activation.
const captainAnimations = [
  {effect: startFooterCat},
  {effect: captainBrown},
  {effect: captainPink},
  {effect: captainMirror},
  {effect: captainConfetti},
  // Spring: squash, jump, then two smaller rebounds.
  {duration: 1300, frames: [
    {transform: "translateY(0) scale(1, 1)", offset: 0},
    {transform: "translateY(25px) scale(1.18, 0.72)", offset: 0.15},
    {transform: "translateY(-100px) scale(0.9, 1.12)", offset: 0.32},
    {transform: "translateY(15px) scale(1.12, 0.85)", offset: 0.48},
    {transform: "translateY(-48px) scale(0.96, 1.05)", offset: 0.62},
    {transform: "translateY(8px) scale(1.05, 0.94)", offset: 0.74},
    {transform: "translateY(-18px) scale(1, 1)", offset: 0.86},
    {transform: "translateY(0) scale(1, 1)", offset: 1}
  ]},
  // A reluctant shake of the head.
  {duration: 900, frames: [
    {transform: "translateX(0) rotate(0deg)", offset: 0},
    {transform: "translateX(-28px) rotate(-10deg)", offset: 0.14},
    {transform: "translateX(28px) rotate(10deg)", offset: 0.28},
    {transform: "translateX(-22px) rotate(-8deg)", offset: 0.42},
    {transform: "translateX(22px) rotate(8deg)", offset: 0.56},
    {transform: "translateX(-12px) rotate(-4deg)", offset: 0.7},
    {transform: "translateX(12px) rotate(4deg)", offset: 0.84},
    {transform: "translateX(0) rotate(0deg)", offset: 1}
  ]},
  {duration: 800, frames: [
    {transform: "translateY(0) rotate(0deg)", offset: 0},
    {transform: "translateY(8px) rotate(-8deg)", offset: 0.2},
    {transform: "translateY(-45px) rotate(12deg)", offset: 0.45},
    {transform: "translateY(0) rotate(-6deg)", offset: 0.7},
    {transform: "translateY(-10px) rotate(3deg)", offset: 0.85},
    {transform: "translateY(0) rotate(0deg)", offset: 1}
  ]},
  {duration: 950, frames: [
    {transform: "scale(1)", offset: 0},
    {transform: "scale(1.2)", offset: 0.15},
    {transform: "scale(1)", offset: 0.3},
    {transform: "scale(1.3)", offset: 0.45},
    {transform: "scale(1)", offset: 0.65},
    {transform: "scale(1.12)", offset: 0.8},
    {transform: "scale(1)", offset: 1}
  ]},
  {duration: 900, frames: [
    {transform: "rotate(0deg)"},
    {transform: "rotate(360deg)"}
  ]},
  {duration: 1600, frames: skull => {
    const bounds = skull.getBoundingClientRect()
    // SVG transforms use viewBox units, not screen pixels.
    const scale = skull.getScreenCTM().a
    const right = (document.documentElement.clientWidth - bounds.left + 8) / scale
    const left = (-bounds.right - 8) / scale
    return [
      {transform: "translateX(0)", opacity: 1, offset: 0},
      {transform: `translateX(${right}px)`, opacity: 1, offset: 0.48},
      {transform: `translateX(${right}px)`, opacity: 0, offset: 0.49},
      {transform: `translateX(${left}px)`, opacity: 0, offset: 0.51},
      {transform: `translateX(${left}px)`, opacity: 1, offset: 0.52},
      {transform: "translateX(0)", opacity: 1, offset: 1}
    ]
  }}
]
const lastCaptainAnimation = new WeakMap()
document.addEventListener("click", event => {
  const button = event.target.closest("[data-logo-easter-egg]")
  if (!button || document.body.classList.contains("bahia-touring") || window.matchMedia("(prefers-reduced-motion: reduce)").matches) return
  const skull = button.querySelector(".app-brand-skull")
  if (!skull || skull.getAnimations().length) return
  if (!captainAnimations.length) return
  // Optional haptic feedback; unsupported or blocked vibration must not interrupt the animation.
  if (typeof navigator.vibrate === "function") {
    try { navigator.vibrate(12) } catch { /* Browser or device policy may block vibration. */ }
  }
  const available = captainAnimations.filter(animation => animation.effect !== startFooterCat || !footerCatActive())
  const choices = available.length > 1
    ? available.filter(animation => animation !== lastCaptainAnimation.get(button))
    : available
  const animation = choices[Math.floor(Math.random() * choices.length)]
  lastCaptainAnimation.set(button, animation)
  animation.effect?.(button)
  if (!animation.frames) return
  const frames = typeof animation.frames === "function" ? animation.frames(skull) : animation.frames
  skull.animate(frames, {duration: animation.duration, easing: "ease-in-out"})
})

// expose liveSocket on window for web console debug logs and latency simulation:
// >> liveSocket.enableDebug()
// >> liveSocket.enableLatencySim(1000)  // enabled for duration of browser session
// >> liveSocket.disableLatencySim()
window.liveSocket = liveSocket

// The lines below enable quality of life phoenix_live_reload
// development features:
//
//     1. stream server logs to the browser console
//     2. click on elements to jump to their definitions in your code editor
//
if (process.env.NODE_ENV === "development") {
  window.addEventListener("phx:live_reload:attached", ({detail: reloader}) => {
    // Enable server log streaming to client.
    // Disable with reloader.disableServerLogs()
    reloader.enableServerLogs()

    // Open configured PLUG_EDITOR at file:line of the clicked element's HEEx component
    //
    //   * click with "c" key pressed to open at caller location
    //   * click with "d" key pressed to open at function component definition location
    let keyDown
    window.addEventListener("keydown", e => keyDown = e.key)
    window.addEventListener("keyup", _e => keyDown = null)
    window.addEventListener("click", e => {
      if(keyDown === "c"){
        e.preventDefault()
        e.stopImmediatePropagation()
        reloader.openEditorAtCaller(e.target)
      } else if(keyDown === "d"){
        e.preventDefault()
        e.stopImmediatePropagation()
        reloader.openEditorAtDef(e.target)
      }
    }, true)

    window.liveReloader = reloader
  })
}

listenForPushNavigation()
updatePushWorker()
if (document.querySelector("#pin-form")) applyAppBadge(false)
