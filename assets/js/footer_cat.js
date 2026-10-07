const size = 72
const margin = 8
const pause = 2000
const sleep = 60000
let active = null

// The v4 atlas uses four transition frames at 6 fps, played once.
const transition = 4 * 1000 / 6
const transitionFrame = elapsed => Math.min(3, Math.floor(elapsed * 6 / 1000))
const sleepingAt = legDuration => 2 * legDuration + pause + 3 * transition
export const catDuration = legDuration => sleepingAt(legDuration) + sleep

export function catScene(elapsed, width, legDuration) {
  const left = margin
  const right = Math.max(left, width - size - margin)
  const center = (left + right) / 2
  const seatedAt = legDuration + transition
  const risingAt = seatedAt + pause
  const walkingAt = risingAt + transition
  const lyingAt = walkingAt + legDuration
  const asleepAt = sleepingAt(legDuration)
  if (elapsed < legDuration) {
    return {phase: "walking", x: left + (center - left) * elapsed / legDuration, row: 2, frame: Math.floor(elapsed / 125) % 4}
  }
  if (elapsed < seatedAt) {
    return {phase: "sitting-down", x: center, row: 5, frame: transitionFrame(elapsed - legDuration)}
  }
  if (elapsed < risingAt) return {phase: "sitting", x: center, row: 5, frame: 3}
  if (elapsed < walkingAt) {
    return {phase: "standing-up", x: center, row: 5, frame: 3 - transitionFrame(elapsed - risingAt)}
  }
  if (elapsed < lyingAt) {
    const walking = elapsed - walkingAt
    return {phase: "walking", x: center + (right - center) * walking / legDuration, row: 2, frame: Math.floor(walking / 125) % 4}
  }
  if (elapsed < asleepAt) {
    return {phase: "lying-down", x: right, row: 6, frame: transitionFrame(elapsed - lyingAt)}
  }
  const sleeping = elapsed - asleepAt
  return {phase: sleeping < sleep ? "sleeping" : "done", x: right, row: 4, frame: Math.floor(sleeping / 500) % 4}
}

export function footerCatActive() { return active !== null }

export async function startFooterCat(button) {
  if (active || window.matchMedia("(prefers-reduced-motion: reduce)").matches) return
  const host = button.closest(".app-brand-footer")?.querySelector("#footer-cat-stage")
  if (!host) return
  const run = {raf: null, timer: null, host: null}
  active = run
  const cleanup = () => {
    cancelAnimationFrame(run.raf)
    clearTimeout(run.timer)
    run.host?.replaceChildren()
    document.body.classList.remove("bahia-touring")
    window.removeEventListener("pagehide", cleanup)
    if (active === run) active = null
  }
  window.addEventListener("pagehide", cleanup)
  try {
    const atlas = new Image()
    atlas.src = button.dataset.catAtlas
    await atlas.decode()
    if (active !== run || !button.isConnected || !host.isConnected) { cleanup(); return }
    const sprite = document.createElement("div")
    sprite.className = "footer-cat"
    sprite.style.backgroundImage = `url(${JSON.stringify(atlas.src)})`
    host.appendChild(sprite)
    run.host = host
    document.body.classList.add("bahia-touring")
    const legDuration = Math.max(1000, (host.clientWidth - size - 2 * margin) / 2 / 100 * 1000)
    const started = performance.now()
    const duration = catDuration(legDuration)
    // A timer also removes the cat if animation frames are suspended in the background.
    run.timer = setTimeout(cleanup, duration)
    const tick = now => {
      if (!host.isConnected) { cleanup(); return }
      const scene = catScene(now - started, host.clientWidth, legDuration)
      if (scene.phase === "done") { cleanup(); return }
      if (scene.phase === "sleeping") document.body.classList.remove("bahia-touring")
      sprite.dataset.phase = scene.phase
      sprite.style.transform = `translateX(${scene.x}px)`
      sprite.style.backgroundPosition = `${-scene.frame * size}px ${-scene.row * size}px`
      run.raf = requestAnimationFrame(tick)
    }
    tick(started)
  } catch {
    cleanup()
  }
}
