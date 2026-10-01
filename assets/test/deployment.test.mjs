import {test, beforeEach} from "node:test"
import assert from "node:assert/strict"
import {watchDeploymentVersion} from "../js/deployment.js"

let check, listeners, reloads, remote, requests
beforeEach(() => {
  listeners = {}; reloads = 0; remote = "first"; requests = 0
  globalThis.document = {
    hidden: false,
    querySelector: () => ({content: "first"}),
    addEventListener: (event, callback) => { listeners[event] = callback }
  }
  globalThis.window = {
    location: {reload: () => { reloads++ }},
    addEventListener: (event, callback) => { listeners[event] = callback },
    setInterval: callback => { listeners.interval = callback }
  }
  globalThis.fetch = async (url, options) => {
    requests++
    assert.equal(url, "/app-version")
    assert.equal(options.cache, "no-store")
    assert.equal(options.redirect, "error")
    return {ok: true, json: async () => ({version: remote})}
  }
  watchDeploymentVersion({onOpen: callback => { check = callback }})
})
const settle = () => new Promise(resolve => setImmediate(resolve))

test("the current version stays open; a new deployment reloads exactly once", async () => {
  await settle()
  assert.equal(reloads, 0)
  remote = "second"
  await check()
  await listeners.interval()
  assert.equal(reloads, 1)
})

test("offline and invalid responses do not reload; recovery detects the deployment", async () => {
  await settle()
  const original = fetch
  globalThis.fetch = async () => { throw new Error("offline") }
  await check()
  globalThis.fetch = async () => ({ok: false})
  await check()
  globalThis.fetch = async () => ({ok: true, json: async () => ({})})
  await check()
  assert.equal(reloads, 0)
  globalThis.fetch = original
  remote = "second"
  await listeners.online()
  assert.equal(reloads, 1)
})

test("a suspended app checks again when visible without polling in the background", async () => {
  await settle()
  document.hidden = true
  remote = "second"
  const previous = requests
  await listeners.interval()
  assert.equal(requests, previous)
  assert.equal(reloads, 0)
  document.hidden = false
  await listeners.visibilitychange()
  assert.equal(reloads, 1)
})
