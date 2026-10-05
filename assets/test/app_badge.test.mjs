import test from "node:test"
import assert from "node:assert/strict"
import {applyAppBadge, AppBadge} from "../js/app_badge.js"

test("a numeric attention badge clears only with confirmed read state", async () => {
  const calls = []
  const target = {setAppBadge: async n => calls.push(n), clearAppBadge: async () => calls.push(0)}
  await applyAppBadge(4, target)
  await applyAppBadge(null, target)
  await applyAppBadge(0, target)
  assert.deepEqual(calls, [4, 0])
  await applyAppBadge(4, {})
  await applyAppBadge(4, {setAppBadge: async () => { throw new Error("denied") }})
})

test("foreground synchronization preserves the badge on failure and cleans up listeners", async () => {
  const calls = [], listeners = new Map()
  Object.defineProperty(globalThis, "navigator", {configurable: true, value: {
    setAppBadge: async n => calls.push(n), clearAppBadge: async () => calls.push(0)
  }})
  globalThis.window = {addEventListener: (n, f) => listeners.set(n, f), removeEventListener: n => listeners.delete(n)}
  globalThis.document = {...window, visibilityState: "visible"}
  globalThis.fetch = async () => ({ok: true, json: async () => ({count: 4})})
  const hook = {...AppBadge}
  const tick = () => new Promise(resolve => setImmediate(resolve))
  try {
    hook.mounted()
    await tick()
    assert.deepEqual(calls, [4])
    globalThis.fetch = async () => { throw new Error("offline") }
    hook.updated()
    await tick()
    assert.deepEqual(calls, [4])
    globalThis.fetch = async () => ({ok: true, json: async () => ({count: 0})})
    listeners.get("focus")()
    await tick()
    assert.deepEqual(calls, [4, 0])
    document.visibilityState = "hidden"
    hook.updated()
    await tick()
    assert.deepEqual(calls, [4, 0])
  } finally { hook.destroyed() }
  assert.equal(listeners.size, 0)
})
