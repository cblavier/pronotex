import {test} from "node:test"
import assert from "node:assert/strict"
import {WeekOverview} from "../js/week_overview.js"

function mount(desktop) {
  const media = {matches: desktop, addEventListener(_, fn) { this.change = fn }, removeEventListener() { this.change = null }}
  const events = []
  const listeners = new Map()
  const pending = new Map()
  let sequence = 0
  const schedule = fn => { pending.set(++sequence, fn); return sequence }
  const viewportListeners = new Map()
  globalThis.window = {
    matchMedia: query => { media.query = query; return media }, innerWidth: 390, innerHeight: 844,
    addEventListener: (name, fn) => listeners.set(name, fn),
    removeEventListener: name => listeners.delete(name),
    setTimeout: schedule, clearTimeout: id => pending.delete(id),
    requestAnimationFrame: schedule, cancelAnimationFrame: id => pending.delete(id),
    visualViewport: {
      width: 390, height: 844,
      addEventListener: (name, fn) => viewportListeners.set(name, fn),
      removeEventListener: name => viewportListeners.delete(name)
    }
  }
  globalThis.document = {body: {style: {overflow: "auto"}}, activeElement: null}
  const hook = {...WeekOverview, pushEvent: name => events.push(name), el: {
    open: false,
    toggleAttribute(name, enabled) { this[name] = enabled },
    addEventListener(_, fn) { this.cancel = fn }, removeEventListener() {},
    show() { this.open = true; this.presentation = "inline" },
    showModal() { this.open = true; this.presentation = "modal" },
    close() { this.open = false }
  }}
  hook.mounted()
  const tick = () => {
    const callbacks = [...pending.values()]
    pending.clear()
    callbacks.forEach(fn => fn())
  }
  return {hook, media, events, listeners, viewportListeners, pending, tick}
}

test("desktop leaves app navigation interactive and page scrolling enabled", () => {
  const {hook} = mount(true)
  assert.equal(hook.el.presentation, "inline")
  assert.equal(document.body.style.overflow, "auto")
  hook.updated()
  assert.equal(hook.el.presentation, "inline")
  hook.destroyed()
  assert.equal(hook.el.open, false)
})

test("rotation keeps content hidden until dimensions settle, including during live updates", () => {
  const {hook, listeners, viewportListeners, pending, tick} = mount(false)
  listeners.get("orientationchange")()
  assert.equal(hook.el["data-resizing"], true)
  tick()
  window.innerWidth = 844
  window.innerHeight = 390
  tick()
  tick()
  assert.equal(hook.el["data-resizing"], true)
  viewportListeners.get("resize")()
  assert.equal(pending.size, 1)
  hook.updated()
  assert.equal(hook.el["data-resizing"], true)
  tick()
  tick()
  tick()
  assert.equal(hook.el["data-resizing"], false)
  listeners.get("resize")()
  hook.destroyed()
  assert.equal(pending.size, 0)
  assert.equal(listeners.size, 0)
  assert.equal(viewportListeners.size, 0)
})

test("landscape mobile stays modal and adapts when the viewport crosses the desktop breakpoint", () => {
  const {hook, media, events} = mount(false)
  assert.equal(hook.el.presentation, "modal")
  assert.equal(document.body.style.overflow, "hidden")
  media.matches = true
  media.change()
  assert.equal(hook.el.presentation, "inline")
  assert.equal(document.body.style.overflow, "auto")
  media.matches = false
  media.change()
  assert.equal(hook.el.presentation, "modal")
  hook.el.cancel({preventDefault() {}})
  assert.deepEqual(events, ["close-week-overview"])
  hook.destroyed()
  assert.equal(document.body.style.overflow, "auto")
  assert.equal(media.change, null)
})

test("portrait keeps navigation interactive and restores the weekly modal only in landscape", () => {
  const {hook, media} = mount(true)
  assert.ok(media.query.split(", ").includes("(orientation: portrait)"))
  assert.equal(hook.el.presentation, "inline")
  assert.equal(document.body.style.overflow, "auto")
  media.matches = false
  media.change()
  assert.equal(hook.el.presentation, "modal")
  assert.equal(document.body.style.overflow, "hidden")
  media.matches = true
  media.change()
  hook.updated()
  assert.equal(hook.el.presentation, "inline")
  assert.equal(document.body.style.overflow, "auto")
  hook.destroyed()
})
