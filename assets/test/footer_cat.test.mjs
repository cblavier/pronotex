import test from "node:test"
import assert from "node:assert/strict"
import {catScene, catDuration} from "../js/footer_cat.js"

const transition = 4 * 1000 / 6
const leg = 1580
const seatedAt = leg + transition
const risingAt = seatedAt + 2000
const walkingAt = risingAt + transition
const lyingAt = walkingAt + leg
const sleepingAt = 2 * leg + 2000 + 3 * transition

test("the v4 transitions play once, in order, without moving the cat", () => {
  for (const [start, phase, row, frames, x] of [
    [leg, "sitting-down", 5, [0, 1, 2, 3], 179],
    [risingAt, "standing-up", 5, [3, 2, 1, 0], 179],
    [lyingAt, "lying-down", 6, [0, 1, 2, 3], 350]
  ]) {
    frames.forEach((frame, i) => {
      assert.deepEqual(catScene(start + (i + 0.5) * 1000 / 6, 430, leg), {phase, x, row, frame})
    })
  }
})

test("two seconds seated and one minute asleep exclude the transitions", () => {
  const width = 430
  assert.deepEqual(catScene(0, width, leg), {phase: "walking", x: 8, row: 2, frame: 0})
  assert.equal(catScene(leg - 1, width, leg).phase, "walking")
  const seated = {phase: "sitting", x: 179, row: 5, frame: 3}
  assert.deepEqual(catScene(seatedAt, width, leg), seated)
  assert.deepEqual(catScene(risingAt - 1, width, leg), seated)
  assert.equal(catScene(risingAt, width, leg).phase, "standing-up")
  assert.equal(catScene(walkingAt, width, leg).phase, "walking")
  assert.deepEqual(catScene(sleepingAt, width, leg), {phase: "sleeping", x: 350, row: 4, frame: 0})
  assert.equal(catScene(sleepingAt + 59999, width, leg).phase, "sleeping")
  assert.equal(catScene(sleepingAt + 60000, width, leg).phase, "done")
  assert.equal(catDuration(leg), sleepingAt + 60000)
})

test("positions follow the viewport width, including rotation", () => {
  for (const width of [320, 430, 932, 1440]) {
    assert.equal(catScene(seatedAt, width, leg).x + 36, width / 2)
    assert.equal(catScene(sleepingAt, width, leg).x + 72, width - 8)
  }
})
