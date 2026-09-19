import { test, expect } from '../test-support/setupAuth'
import { syncLV } from '../utils'
import fs from 'fs'
import path from 'path'

// Splits the bench's single "insert" number into its parts.
//
// The plan reads insert latency (387 ms @5 -> 1 128 ms @115) as server render
// work, because the payload is flat. But an eprof of the LiveView process over
// the whole operation came back at 23 ms of CPU, so the premise needed
// checking: the bench measures three clicks (open picker, pick module set,
// pick module), and each one is a round trip plus a client-side patch of a
// DOM that grows with block count.
//
// For each step this records the server round trip (last frame sent -> last
// frame received) separately from the wall clock Playwright sees.
//
//   pnpm playwright test --config bench/playwright.bench.config.js bench/insert-breakdown.spec.js

const IDS = JSON.parse(fs.readFileSync(path.join(__dirname, 'fixture-ids.json'), 'utf8'))

test.use({ viewport: { width: 1400, height: 1200 }, actionTimeout: 20000 })

const rows = []

const measure = async (page, label, blocks) => {
  const frames = []
  page.on('websocket', (ws) => {
    ws.on('framesent', (d) => {
      if (typeof d.payload === 'string' && !d.payload.includes('"phoenix"')) {
        frames.push({ dir: 'out', t: Date.now(), n: d.payload.length })
      }
    })
    ws.on('framereceived', (d) => {
      if (typeof d.payload === 'string' && !d.payload.includes('"phoenix"')) {
        frames.push({
          dir: 'in',
          t: Date.now(),
          n: d.payload.length,
          p: process.env.BENCH_DUMP ? d.payload : null,
        })
      }
    })
  })

  await page.goto(`/admin/pages/update/${IDS.flat[blocks]}`)
  await syncLV(page, 120000)
  await expect(page.locator('[data-block-uid]').first()).toBeVisible({ timeout: 120000 })
  await page.waitForTimeout(2500)

  const row = { entry: label, blocks: Number(blocks), steps: {} }

  // Long tasks are main-thread blocks over 50 ms — for a LiveView patch that is
  // morphdom walking the DOM. Separates "the browser was busy" from "Playwright
  // was polling for actionability", which the wall clock conflates.
  await page.evaluate(() => {
    window.__longTasks = []
    new PerformanceObserver((list) => {
      for (const entry of list.getEntries()) window.__longTasks.push(entry.duration)
    }).observe({ entryTypes: ['longtask'] })
  })

  const step = async (name, fn) => {
    const mark = frames.length
    await page.evaluate(() => (window.__longTasks = []))
    const t0 = Date.now()
    await fn()
    await syncLV(page, 60000)
    const wall = Date.now() - t0
    const longTasks = await page.evaluate(() => window.__longTasks)
    const slice = frames.slice(mark)
    const firstOut = slice.find((f) => f.dir === 'out')
    const lastIn = slice.filter((f) => f.dir === 'in').pop()
    row.steps[name] = {
      wall,
      // request on the wire -> last byte of the response back. Everything
      // outside this is browser patch time plus Playwright actionability.
      roundTrip: firstOut && lastIn ? lastIn.t - firstOut.t : null,
      mainThread: Math.round(longTasks.reduce((a, d) => a + d, 0)),
      bytesIn: slice.filter((f) => f.dir === 'in').reduce((a, f) => a + f.n, 0),
      frames: slice.length,
    }

    // BENCH_DUMP=1 writes each step's inbound frames so their component
    // composition can be read offline — which components a frame touches is
    // what decides how much DOM morphdom has to walk.
    if (process.env.BENCH_DUMP) {
      fs.writeFileSync(
        path.join(__dirname, `insert-${name}-${blocks}.json`),
        JSON.stringify(slice.filter((f) => f.dir === 'in' && f.p).map((f) => f.p), null, 2)
      )
    }
  }

  await step('openPicker', () => page.getByRole('button', { name: 'Add block' }).last().click())
  await step('pickModuleSet', () =>
    page.getByRole('button', { name: '05 LIVE PREVIEW TEST' }).click()
  )
  await step('pickModule', () => page.getByRole('button', { name: 'Styled Header' }).click())

  const total = Object.values(row.steps).reduce((a, s) => a + s.wall, 0)
  row.total = total
  rows.push(row)
  console.log('INSERT_BREAKDOWN ' + JSON.stringify(row))
}

test.describe('BENCH: insert breakdown', () => {
  test.setTimeout(600000)

  for (const size of ['5', '40', '115']) {
    test(`insert steps, ${size} root blocks`, async ({ page }) => {
      await measure(page, `flat-${size}`, size)
    })
  }

  test.afterAll(() => {
    if (rows.length) console.log('\nINSERT_BREAKDOWN_ALL ' + JSON.stringify(rows, null, 2))
  })
})
