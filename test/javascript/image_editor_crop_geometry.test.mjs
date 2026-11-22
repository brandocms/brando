import { test } from 'node:test'
import assert from 'node:assert/strict'
import { readFile } from 'node:fs/promises'

const source = await readFile(new URL('../../assets/src/hooks/ImageEditor/cropGeometry.js', import.meta.url), 'utf8')
const { calculateCropRegion, centerFocalOf, focalInRegion, shiftFocalWithFrame } =
  await import(`data:text/javascript;base64,${Buffer.from(source).toString('base64')}`)

// A 2500×1875 photo with a 1000×375 size: the frame is the full width, 937.5 rows tall.
const W = 2500
const H = 1875
const RATIO = 1000 / 375

test('a position-mode point places the frame where the server cuts', () => {
  // Sizing.calculate_anchor/1: resized to 1000×750, anchor 0.4 × (750 − 375) = 150,
  // which is row 375 of the original.
  const region = calculateCropRegion(50, 40, W, H, RATIO, 1, 'position')

  assert.equal(region.width, 2500)
  assert.equal(region.top, 375)
  assert.ok(Math.abs(region.top + region.height - 1312.5) <= 1)
})

test('a centre-mode point centres the frame on it', () => {
  const region = calculateCropRegion(50, 40, W, H, RATIO, 1, 'center')

  assert.equal(region.top, 281)
  assert.deepEqual(region, calculateCropRegion(50, 40, W, H, RATIO, 1))
})

test('position mode at 0 and 100 puts the frame against that edge', () => {
  assert.equal(calculateCropRegion(0, 0, W, H, RATIO, 1, 'position').top, 0)

  const bottom = calculateCropRegion(100, 100, W, H, RATIO, 1, 'position')
  assert.equal(bottom.top + bottom.height, H)
})

test('centre mode at 0 and 100 clamps the frame to the image', () => {
  assert.equal(calculateCropRegion(0, 0, W, H, RATIO, 1, 'center').top, 0)

  const bottom = calculateCropRegion(100, 100, W, H, RATIO, 1, 'center')
  assert.equal(bottom.top + bottom.height, H)
})

test('position mode places a zoomed frame on both axes', () => {
  const region = calculateCropRegion(25, 40, W, H, RATIO, 2, 'position')

  assert.equal(region.width, 1250)
  assert.equal(region.left, Math.round(0.25 * (W - 1250)))
  assert.equal(region.top, Math.round(0.4 * (H - region.height)))
})

test('the centre of a position-mode frame places the same frame in centre mode', () => {
  for (const [x, y, zoom] of [[50, 40, 1], [0, 0, 1], [100, 100, 1], [25, 70, 2], [0, 100, 3]]) {
    const before = calculateCropRegion(x, y, W, H, RATIO, zoom, 'position')
    const focal = centerFocalOf(before, W, H)
    const after = calculateCropRegion(focal.x, focal.y, W, H, RATIO, zoom, 'center')

    assert.deepEqual(after, before, `point ${x},${y} at zoom ${zoom}`)
  }
})

test('the converted point of the example is the middle of rows 375–1312', () => {
  const focal = centerFocalOf(calculateCropRegion(50, 40, W, H, RATIO, 1, 'position'), W, H)

  assert.equal(focal.x, 50)
  assert.ok(Math.abs(focal.y - (375 + 937.5 / 2) / H * 100) < 0.05)
})

test('dragging a converted frame moves it with the pointer until the edge', () => {
  const region = calculateCropRegion(50, 40, W, H, RATIO, 1, 'position')
  const start = centerFocalOf(region, W, H)

  const moved = shiftFocalWithFrame(start.y, 100, region.height, H)
  assert.equal(calculateCropRegion(50, moved, W, H, RATIO, 1).top, 475)

  const pastEdge = shiftFocalWithFrame(start.y, 5000, region.height, H)
  assert.equal(calculateCropRegion(50, pastEdge, W, H, RATIO, 1).top, H - region.height)
})

// A 1000×1000 photo, square crop at 2× zoom, position-mode point (20, 50): the
// editor exports columns 100–599, where the pin (column 200) is 20 % across.
test('a zoomed export keeps a position-mode pin on its place in the photo', () => {
  const region = calculateCropRegion(20, 50, 1000, 1000, 1, 2, 'position')
  assert.deepEqual(region, { left: 100, top: 250, width: 500, height: 500 })

  assert.deepEqual(focalInRegion(20, 50, region, 1000, 1000), { x: 20, y: 50 })
})

test('the server cuts the other sizes from a zoomed export where the previews showed them', () => {
  const region = calculateCropRegion(20, 50, 1000, 1000, 1, 2, 'position')
  const focal = focalInRegion(20, 50, region, 1000, 1000)

  // The 1:2 preview at 2× zoom, against the band the server cuts at 1:2 from
  // the exported file, in the same mode.
  const preview = calculateCropRegion(20, 50, 1000, 1000, 0.5, 2, 'position')
  const cut = calculateCropRegion(focal.x, focal.y, region.width, region.height, 0.5, 1, 'position')

  assert.equal(preview.left, 150)
  assert.deepEqual(
    { left: region.left + cut.left, top: region.top + cut.top, width: cut.width, height: cut.height },
    preview
  )
})

test('a zoomed export re-expresses a centre-mode pin in the exported file', () => {
  const region = { left: 0, top: 0, width: 500, height: 400 }

  assert.deepEqual(focalInRegion(25, 25, region, 1000, 800), { x: 50, y: 50 })
})
