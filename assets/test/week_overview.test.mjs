import {test} from "node:test"
import assert from "node:assert/strict"
import {WeekOverview} from "../js/week_overview.js"

function mount(desktop) {
  const media = {matches: desktop, addEventListener(_, fn) { this.change = fn }, removeEventListener() { this.change = null }}
  const events = []
  globalThis.window = {
    matchMedia: query => { media.query = query; return media }
  }
  globalThis.document = {body: {style: {overflow: "auto"}}, activeElement: null}
  const hook = {...WeekOverview, pushEvent: name => events.push(name), el: {
    open: false,
    addEventListener(_, fn) { this.cancel = fn }, removeEventListener() {},
    show() { this.open = true; this.presentation = "inline" },
    showModal() { this.open = true; this.presentation = "modal" },
    close() { this.open = false }
  }}
  hook.mounted()
  return {hook, media, events}
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
