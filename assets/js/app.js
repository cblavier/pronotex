import {MessageComposer} from "./message_composer"
import {NotificationBanners} from "./notification_banners"
import {WeekOverview} from "./week_overview"
import {updatePushWorker, listenForPushNavigation} from "./push"
// If you want to use Phoenix channels, run `mix help phx.gen.channel`
// to get started and then uncomment the line below.
// import "./user_socket.js"

// You can include dependencies in two ways.
//
// The simplest option is to put them in assets/vendor and
// import them using relative paths:
//
//     import "../vendor/some-package.js"
//
// Alternatively, you can `npm install some-package --prefix assets` and import
// them using a path starting with the package name:
//
//     import "some-package"
//
// If you have dependencies that try to import CSS, esbuild will generate a separate `app.css` file.
// To load it, simply add a second `<link>` to your `root.html.heex` file.

// Include phoenix_html to handle method=PUT/DELETE in forms and buttons.
import "phoenix_html"
// Establish Phoenix Socket and LiveView configuration.
import {Socket} from "phoenix"
import {LiveSocket} from "phoenix_live_view"
import {hooks as colocatedHooks} from "phoenix-colocated/pronotex"
import topbar from "../vendor/topbar"
import {Settings} from "./settings"
import {RememberPage, restoreLastPage} from "./last_page"

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
// mounted runs after the first successful LiveView join, including transport fallback.
// Keep readiness for this document so navigation and reconnects never replay the splash.
const startupSplashStarted = performance.now()
const startupSplashMinimumMs = 750
const isStandalone = window.matchMedia("(display-mode: standalone)").matches
const finishStartupSplash = () => {
  document.documentElement.classList.add("app-ready")
  document.querySelector(".page-shell")?.removeAttribute("inert")
}
const StartupSplash = {
  mounted() {
    const remaining = isStandalone && !document.documentElement.classList.contains("app-ready")
      ? startupSplashMinimumMs - (performance.now() - startupSplashStarted)
      : 0
    if (remaining > 0) this.startupTimer = setTimeout(finishStartupSplash, remaining)
    else finishStartupSplash()
  },
  destroyed() {
    clearTimeout(this.startupTimer)
    finishStartupSplash()
  }
}
if (isStandalone &&
    document.querySelector("#startup-splash") && !document.documentElement.classList.contains("app-ready")) {
  document.querySelector(".page-shell")?.setAttribute("inert", "")
}
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
  hooks: {...colocatedHooks, MessageComposer, NotificationBanners, WeekOverview, AgendaScroll, StartupSplash, Settings, RememberPage},
})

// Show progress bar on live navigation and form submits
topbar.config({barColors: {0: "#29d"}, shadowColor: "rgba(0, 0, 0, .3)"})
window.addEventListener("phx:page-loading-start", _info => topbar.show(300))
window.addEventListener("phx:page-loading-stop", _info => topbar.hide())

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

// connect if there are any LiveViews on the page
if (!restoreLastPage()) liveSocket.connect()

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

// Sample one color per 18px square, then expand it into a chunky pixel.
let cleanupCaptainPixelate
const captainPixelate = () => {
  cleanupCaptainPixelate?.()
  const svg = document.createElementNS("http://www.w3.org/2000/svg", "svg")
  svg.setAttribute("aria-hidden", "true")
  svg.setAttribute("width", "0")
  svg.setAttribute("height", "0")
  svg.style.position = "absolute"
  svg.innerHTML = `
    <filter id="captain-pixel-filter" x="0" y="0" width="100%" height="100%"
            primitiveUnits="userSpaceOnUse" color-interpolation-filters="sRGB">
      <feFlood x="8" y="8" width="2" height="2" />
      <feComposite in2="SourceGraphic" operator="in" x="0" y="0" width="12" height="12" />
      <feTile result="samples" />
      <feComposite in="SourceGraphic" in2="samples" operator="in" />
      <feMorphology operator="dilate" radius="9" />
    </filter>`
  document.body.appendChild(svg)
  document.body.classList.add("captain-pixelated")
  const cleanup = () => {
    document.body.classList.remove("captain-pixelated")
    svg.remove()
    window.clearTimeout(timer)
    window.removeEventListener("phx:page-loading-start", cleanup)
  }
  cleanupCaptainPixelate = cleanup
  const timer = window.setTimeout(cleanup, 5000)
  window.addEventListener("phx:page-loading-start", cleanup, {once: true})
}

let cleanupCaptainPink
const captainPink = () => {
  cleanupCaptainPink?.()
  document.body.classList.add("captain-pink")
  const cleanup = () => {
    document.body.classList.remove("captain-pink")
    window.clearTimeout(timer)
    window.removeEventListener("phx:page-loading-start", cleanup)
  }
  cleanupCaptainPink = cleanup
  const timer = window.setTimeout(cleanup, 10000)
  window.addEventListener("phx:page-loading-start", cleanup, {once: true})
}

// Short surprises from the captain, including keyboard activation.
const captainAnimations = [
  {effect: captainPink},
  {effect: captainPixelate},
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
  // Gently bob and roll on an imaginary wave.
  {duration: 2000, frames: [
    {transform: "translate(0, 0) rotate(0deg)", offset: 0},
    {transform: "translate(-25px, -25px) rotate(-12deg)", offset: 0.2},
    {transform: "translate(25px, 15px) rotate(12deg)", offset: 0.4},
    {transform: "translate(-20px, -20px) rotate(-9deg)", offset: 0.6},
    {transform: "translate(15px, 10px) rotate(6deg)", offset: 0.8},
    {transform: "translate(0, 0) rotate(0deg)", offset: 1}
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
  {duration: 1100, frames: [
    {opacity: 1, transform: "scale(1)", offset: 0},
    {opacity: 0, transform: "scale(0.65)", offset: 0.35},
    {opacity: 0, transform: "scale(0.65)", offset: 0.55},
    {opacity: 1, transform: "scale(1.08)", offset: 0.85},
    {opacity: 1, transform: "scale(1)", offset: 1}
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
// Safari (including installed iOS apps) cannot reliably render this SVG filter.
const availableCaptainAnimations = captainAnimations.filter(animation =>
  animation.effect !== captainPixelate || !/^Apple/.test(navigator.vendor || "")
)
const lastCaptainAnimation = new WeakMap()
document.addEventListener("click", event => {
  const button = event.target.closest("[data-logo-easter-egg]")
  if (!button || window.matchMedia("(prefers-reduced-motion: reduce)").matches) return
  const skull = button.querySelector(".app-brand-skull")
  if (!skull || skull.getAnimations().length) return
  if (!availableCaptainAnimations.length) return
  // Optional haptic feedback; unsupported or blocked vibration must not interrupt the animation.
  if (typeof navigator.vibrate === "function") {
    try { navigator.vibrate(12) } catch { /* Browser or device policy may block vibration. */ }
  }
  const choices = availableCaptainAnimations.length > 1
    ? availableCaptainAnimations.filter(animation => animation !== lastCaptainAnimation.get(button))
    : availableCaptainAnimations
  const animation = choices[Math.floor(Math.random() * choices.length)]
  lastCaptainAnimation.set(button, animation)
  animation.effect?.()
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
