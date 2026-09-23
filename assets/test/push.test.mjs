import {test, beforeEach} from "node:test"
import assert from "node:assert/strict"
import {readFileSync} from "node:fs"
import vm from "node:vm"
import {pushSupported, pushState, enablePush, disablePush, listenForPushNavigation, updatePushWorker} from "../js/push.js"

let calls, subscription, registration
const key = Buffer.from([4, ...Array(64).fill(1)]).toString("base64url")
beforeEach(() => {
  calls = []
  subscription = {
    options: {applicationServerKey: Uint8Array.from(Buffer.from(key, "base64url")).buffer},
    toJSON: () => ({endpoint: "https://web.push.apple.com/test", keys: {p256dh: key, auth: "test"}}),
    unsubscribe: async () => { calls.push("unsubscribe"); return true }
  }
  registration = {pushManager: {
    getSubscription: async () => subscription,
    subscribe: async options => { calls.push("subscribe"); assert.equal(options.userVisibleOnly, true); return subscription }
  }}
  globalThis.window = {isSecureContext: true, Notification: {}, PushManager: {}}
  Object.defineProperty(globalThis, "navigator", {configurable: true, value: {
    userAgent: "iPhone", platform: "iPhone", standalone: true,
    serviceWorker: {
      register: async () => { calls.push("register"); return registration },
      ready: Promise.resolve(registration), getRegistration: async () => registration
    }
  }})
  globalThis.Notification = {permission: "default", requestPermission: () => { calls.push("permission"); return Promise.resolve("granted") }}
  globalThis.matchMedia = () => ({matches: false})
  globalThis.document = {querySelector: () => ({content: "csrf-test"})}
  globalThis.fetch = async (path, options) => {
    calls.push(options.method)
    assert.equal(options.credentials, "same-origin")
    assert.equal(options.headers["x-csrf-token"], "csrf-test")
    return {ok: true, json: async () => ({enabled: true, publicKey: key})}
  }
})

test("permission is requested synchronously within the user's gesture, before registration/network", async () => {
  const enabling = enablePush(key)
  assert.deepEqual(calls, ["permission"])
  assert.equal(await enabling, true)
  assert.deepEqual(calls, ["permission", "register", "POST"])
})

test("permission denial neither registers nor subscribes", async () => {
  Notification.requestPermission = async () => "denied"
  assert.equal(await enablePush(key), false)
  assert.deepEqual(calls, [])
})

test("the switch is active only with server and browser subscriptions and permission", async () => {
  Notification.permission = "granted"
  assert.equal((await pushState()).enabled, true)
  subscription = null
  assert.equal((await pushState()).enabled, false)
})

test("unsubscribe removes backend registration first and does not mask network errors", async () => {
  await disablePush()
  assert.deepEqual(calls, ["DELETE", "unsubscribe"])
  calls.length = 0
  globalThis.fetch = async () => ({ok: false})
  await assert.rejects(disablePush())
  assert.deepEqual(calls, [])
})

test("iPhone requires installation and HTTPS", () => {
  assert.equal(pushSupported(), true)
  navigator.standalone = false
  assert.equal(pushSupported(), false)
  navigator.standalone = true
  window.isSecureContext = false
  assert.equal(pushSupported(), false)
})

function worker() {
  const handlers = {}, displayed = [], opened = []
  const self = {
    location: {origin: "https://notes.example"},
    addEventListener: (name, handler) => { handlers[name] = handler },
    registration: {showNotification: async (title, options) => displayed.push({title, options})},
    clients: {matchAll: async () => [], openWindow: async url => opened.push(url)}
  }
  vm.runInNewContext(readFileSync(new URL("../../priv/static/push-sw.js", import.meta.url), "utf8"), {self, URL})
  return {handlers, displayed, opened, self}
}

test("push displays a notification and the click opens the child's notes", async () => {
  const {handlers, displayed, opened} = worker()
  let done
  handlers.push({data: {json: () => ({title: "Edgar a eu de nouvelles notes", url: "/edgar/notes?period=semester1", tag: "batch-1"})}, waitUntil: p => {done = p}})
  await done
  assert.equal(displayed.length, 1)
  assert.equal(displayed[0].title, "Edgar a eu de nouvelles notes")
  handlers.notificationclick({notification: {close() {}, data: displayed[0].options.data}, waitUntil: p => {done = p}})
  await done
  assert.deepEqual(opened, ["https://notes.example/edgar/notes?period=semester1"])
})

test("a payload cannot open an external site", async () => {
  const {handlers, opened} = worker()
  let done
  handlers.notificationclick({notification: {close() {}, data: {url: "https://evil.test"}}, waitUntil: p => {done = p}})
  await done
  assert.deepEqual(opened, [])
})

test("an existing window receives the target even if native navigation fails", async () => {
  const {handlers, opened, self} = worker()
  const messages = []
  self.clients.matchAll = async () => [{url: "https://notes.example/victor", postMessage: msg => messages.push(msg), navigate: async () => {throw new Error("suspended")}}]
  let done
  handlers.notificationclick({notification: {close() {}, data: {url: "/edgar/notes"}}, waitUntil: p => {done = p}})
  await done
  assert.equal(messages[0].url, "https://notes.example/edgar/notes")
  assert.deepEqual(opened, ["https://notes.example/edgar/notes"])
})

test("page opens the notes target from the worker, rejects other origins", () => {
  let handler
  const visited = []
  navigator.serviceWorker.addEventListener = (_, callback) => {handler = callback}
  window.location = {origin: "https://notes.example", assign: url => visited.push(url)}
  listenForPushNavigation()
  handler({data: {type: "OPEN_NOTES", url: "https://evil.test/edgar/notes"}})
  handler({data: {type: "OPEN_NOTES", url: "https://notes.example/edgar/notes?period=semester1"}})
  assert.deepEqual(visited, ["https://notes.example/edgar/notes?period=semester1"])
})

test("existing worker updates without a new permission request", async () => {
  registration.update = async () => calls.push("update")
  await updatePushWorker()
  assert.deepEqual(calls, ["update"])
})
