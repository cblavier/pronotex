import {test, beforeEach} from "node:test"
import assert from "node:assert/strict"
import {appPath, restoreLastPage, RememberPage} from "../js/last_page.js"

let stored, visited, element
const origin = "https://notes.example"
beforeEach(() => {
  stored = new Map()
  visited = []
  element = {dataset: {pageAccount: "family", pageUrl: "/", pageReady: "false"}}
  globalThis.document = {querySelector: () => element}
  globalThis.window = {
    matchMedia: () => ({matches: true}),
    navigator: {},
    location: {origin, pathname: "/", search: "", hash: "", replace: path => visited.push(path)},
    localStorage: {
      getItem: key => stored.get(key) ?? null,
      setItem: (key, value) => stored.set(key, value),
      removeItem: key => stored.delete(key)
    }
  }
})

function remember(url, ready = "true") {
  element.dataset.pageUrl = url
  element.dataset.pageReady = ready
  RememberPage.updated.call({...RememberPage, el: element})
}

test("browser navigation neither restores nor overwrites the PWA's saved page", () => {
  remember("/victor/notes")
  const saved = stored.get("captain-last-page:family")
  window.matchMedia = () => ({matches: false})
  remember("/edgar/devoirs")
  assert.equal(restoreLastPage(), false)
  assert.deepEqual(visited, [])
  assert.equal(stored.get("captain-last-page:family"), saved)
})

test("iOS standalone mode also remembers and restores the last page", () => {
  window.matchMedia = () => ({matches: false})
  window.navigator.standalone = true
  remember("/victor/notes")
  assert.equal(restoreLastPage(), true)
  assert.deepEqual(visited, ["/victor/notes"])
})

test("a later launch restores the last page including the child and selected period", () => {
  remember("/edgar/devoirs?week=2026-09-21")
  remember("/victor/notes?period=semester2")
  assert.equal(restoreLastPage(), true)
  assert.deepEqual(visited, ["/victor/notes?period=semester2"])
})

test("loading and the default root cannot overwrite the last successful page", () => {
  remember("/victor/menu")
  remember("/")
  remember("/edgar/notes", "false")
  assert.equal(JSON.parse(stored.get("captain-last-page:family")).path, "/victor/menu")
})

test("direct navigation, including notification destinations, takes precedence", () => {
  remember("/victor/devoirs")
  for (const path of ["/edgar/notes", "/edgar", "/victor/messages/thread"]) {
    window.location.pathname = path
    assert.equal(restoreLastPage(), false)
  }
  assert.deepEqual(visited, [])
})

test("each profile has its own saved page and login does not overwrite it", () => {
  remember("/victor/notes")
  element.dataset.pageAccount = "child-1"
  assert.equal(restoreLastPage(), false)
  remember("/edgar/devoirs")
  element.dataset.pageAccount = "family"
  assert.equal(restoreLastPage(), true)
  assert.deepEqual(visited, ["/victor/notes"])
  element = null
  assert.equal(restoreLastPage(), false)
  assert.equal(JSON.parse(stored.get("captain-last-page:family")).path, "/victor/notes")
})

test("lesson and message details survive a restart without storing their content", () => {
  for (const path of ["/victor?week=2026-09-21&lesson=abc%2F123", "/victor/messages/thread%23abc", "/victor/reglages", "/%C3%A9lo%C3%AFse/menu"]) {
    remember(path)
    assert.equal(restoreLastPage(), true)
    assert.equal(visited.at(-1), path)
  }
})

test("malformed or external destinations are discarded without redirect loops", () => {
  for (const value of ["/", "//evil.test/victor", "/\\evil.test/victor", "https://evil.test/victor", "/login", "/logout", "/dev/dashboard", "/push/config", "/victor/unknown", "/victor/notes/extra", "/%ZZ/notes"]) {
    assert.equal(appPath(value, origin), null, value)
    stored.set("captain-last-page:family", JSON.stringify({path: value, savedAt: Date.now()}))
    assert.equal(restoreLastPage(), false)
    assert.equal(stored.has("captain-last-page:family"), false)
  }
  assert.deepEqual(visited, [])
})

test("unavailable local storage never prevents startup or navigation", () => {
  Object.defineProperty(window, "localStorage", {get() { throw new Error("blocked") }})
  assert.equal(restoreLastPage(), false)
  assert.doesNotThrow(() => remember("/edgar/notes"))
})

test("root query parameters are not replaced by a remembered page", () => {
  remember("/edgar/notes")
  window.location.search = "?week=2026-09-21"
  assert.equal(restoreLastPage(), false)
})


test("saved pages expire exactly one hour after the last recorded activity", t => {
  let now = 10000000
  t.mock.method(Date, "now", () => now)
  remember("/victor/notes")
  now += 60 * 60 * 1000 - 1
  assert.equal(restoreLastPage(), true)
  now += 1
  assert.equal(restoreLastPage(), false)
  assert.equal(stored.has("captain-last-page:family"), false)
})

test("legacy entries and invalid timestamps cannot persist indefinitely", () => {
  for (const value of ["/victor/notes", "null", "{}", JSON.stringify({path: "/victor/notes", savedAt: Date.now() + 60000})]) {
    stored.set("captain-last-page:family", value)
    assert.equal(restoreLastPage(), false)
    assert.equal(stored.has("captain-last-page:family"), false)
  }
})

test("leaving records the time, while background updates do not extend the hour", t => {
  let now = 10000000
  t.mock.method(Date, "now", () => now)
  const handlers = new Map()
  document.visibilityState = "visible"
  document.addEventListener = (name, fn) => handlers.set(name, fn)
  window.addEventListener = (name, fn) => handlers.set(name, fn)
  document.removeEventListener = name => handlers.delete(name)
  window.removeEventListener = name => handlers.delete(name)
  element.dataset.pageUrl = "/victor/notes"
  element.dataset.pageReady = "true"
  const hook = {...RememberPage, el: element}
  hook.mounted()
  now += 2 * 60 * 60 * 1000
  document.visibilityState = "hidden"
  handlers.get("visibilitychange")()
  const leftAt = JSON.parse(stored.get("captain-last-page:family")).savedAt
  assert.equal(leftAt, now)
  now += 60 * 60 * 1000
  hook.updated()
  handlers.get("pagehide")()
  assert.equal(JSON.parse(stored.get("captain-last-page:family")).savedAt, leftAt)
  assert.equal(restoreLastPage(), false)
  hook.destroyed()
  assert.equal(handlers.size, 0)
})
