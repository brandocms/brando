import { test, expect } from '../test-support/setupAuth'
import { syncLV, toggleLivePreview, waitForPreviewReady } from '../utils'
import fs from 'fs'
import path from 'path'

// The interactions the other bench specs do not cover: mount until the main
// thread goes idle (block-editor.spec.js stops at "first block visible"),
// keystrokes with the preview closed and open, collapse, opening a block's
// config modal, copy, the outline drawer, draft capture, and how many preview
// renders a burst of keystrokes produces. Each step reports the server round
// trip (see `step` for what it excludes), browser main thread (long tasks) and
// bytes. BENCH_TIMELINE=1 adds every frame of each step to the output.
//
// This replaces the throwaway spec behind the keystroke/collapse/config rows
// of docs/audits/block-editor-client-side-2026-09-13.md.
//
//   pnpm playwright test --config bench/playwright.bench.config.js bench/interactions.spec.js

const IDS = JSON.parse(fs.readFileSync(path.join(__dirname, 'fixture-ids.json'), 'utf8'))

test.use({ viewport: { width: 1400, height: 1200 }, actionTimeout: 20000 })

const rows = []

// [join_ref, ref, topic, event, payload]
const previewEvent = (payload) => {
  const m = /^\[[^,]*,[^,]*,"live_preview:[^"]*","([a-z_]+)"/.exec(payload)
  return m && m[1]
}

const measureEntry = async (page, size) => {
  const frames = []
  page.on('websocket', (ws) => {
    ws.on('framesent', (d) => {
      if (typeof d.payload === 'string' && !d.payload.includes('"phoenix"')) {
        frames.push({ dir: 'out', t: Date.now(), p: d.payload })
      }
    })
    ws.on('framereceived', (d) => {
      if (typeof d.payload === 'string' && !d.payload.includes('"phoenix"')) {
        frames.push({ dir: 'in', t: Date.now(), p: d.payload })
      }
    })
  })

  // Installed before any page script so mount-time long tasks are captured.
  await page.addInitScript(() => {
    window.__longTasks = []
    window.__lastLongTaskEnd = 0
    new PerformanceObserver((list) => {
      for (const e of list.getEntries()) {
        window.__longTasks.push(e.duration)
        window.__lastLongTaskEnd = Math.max(window.__lastLongTaskEnd, e.startTime + e.duration)
      }
    }).observe({ type: 'longtask', buffered: true })
  })

  const row = { entry: `flat-${size}`, blocks: Number(size) }

  // ---- mount, until no long task for 1 s
  let mark = frames.length
  const t0 = Date.now()
  await page.goto(`/admin/pages/update/${IDS.flat[size]}`)
  await syncLV(page, 120000)
  await expect(page.locator('[data-block-uid]').first()).toBeVisible({ timeout: 120000 })
  const ready = Date.now() - t0
  for (;;) {
    const quietFor = await page.evaluate(() => performance.now() - window.__lastLongTaskEnd)
    if (quietFor > 1000) break
    await page.waitForTimeout(200)
  }
  const mountStats = await page.evaluate(() => ({
    mainThread: Math.round(window.__longTasks.reduce((a, d) => a + d, 0)),
    longest: Math.round(Math.max(0, ...window.__longTasks)),
    idleAt: Math.round(window.__lastLongTaskEnd),
    nodes: document.getElementsByTagName('*').length,
  }))
  row.mount = {
    ready,
    idleAt: mountStats.idleAt,
    mainThread: mountStats.mainThread,
    longest: mountStats.longest,
    nodes: mountStats.nodes,
    bytesIn: frames.slice(mark).filter((f) => f.dir === 'in').reduce((a, f) => a + f.p.length, 0),
  }
  await page.waitForTimeout(1000)

  const step = async (fn, settleMs = 600) => {
    const m = frames.length
    await page.evaluate(() => (window.__longTasks = []))
    const t = Date.now()
    await fn()
    await syncLV(page, 60000)
    await page.waitForTimeout(settleMs)
    const wall = Date.now() - settleMs - t
    const slice = frames.slice(m)
    const inbound = slice.filter((f) => f.dir === 'in')
    const outbound = slice.filter((f) => f.dir === 'out')
    // Presence and recovery traffic (focus/blur, draft capture) rides the same
    // socket and lands inside the settle window; counting it made a 4 ms
    // config open read as 600 ms. The round trip runs from the first triggering
    // frame to the last reply to a triggering frame, extended by pushes (diffs
    // from send_update) that follow within 100 ms of each other.
    const ignored = (f) => /"(block_focused|block_blurred|draft_capture|toggle_nav)"/.test(f.p)
    const ref = (f) => (/^\[[^,]*,("[^"]*"|null)/.exec(f.p) || [])[1]
    const triggers = outbound.filter((f) => !ignored(f))
    let roundTrip = null
    if (triggers.length) {
      const refs = new Set(triggers.map(ref))
      const start = triggers[0].t
      let end = Math.max(start, ...inbound.filter((f) => refs.has(ref(f))).map((f) => f.t))
      for (const f of inbound) {
        if (f.t > end && f.t - end <= 100 && ref(f) === 'null') end = f.t
      }
      roundTrip = end - start
    }
    const preview = {}
    for (const f of inbound) {
      const ev = previewEvent(f.p)
      if (ev) preview[ev] = (preview[ev] || 0) + 1
    }
    return {
      wall,
      roundTrip,
      mainThread: await page.evaluate(() => Math.round(window.__longTasks.reduce((a, d) => a + d, 0))),
      bytesIn: inbound.reduce((a, f) => a + f.p.length, 0),
      bytesOut: outbound.reduce((a, f) => a + f.p.length, 0),
      framesOut: outbound.length,
      preview,
      // [ms since step start, direction, bytes, event] — explains round trips
      // that are longer than the server work behind them.
      timeline: process.env.BENCH_TIMELINE
        ? slice.map((f) => [f.t - t, f.dir, f.p.length, (/^\[[^,]*,[^,]*,"[^"]*","([^"]+)"(?:,\{"type":"[^"]*","event":"([^"]+)")?/.exec(f.p) || []).slice(1).filter(Boolean).join(':')])
        : undefined,
    }
  }

  const header = page.locator('.header-block textarea').first()
  const type = async (ch) => {
    await header.pressSequentially(ch, { delay: 20 })
    // validate debounce is 300 ms
    await page.waitForTimeout(400)
  }

  await header.click()
  await type('A') // prime
  await page.waitForTimeout(800)

  // ---- keystroke, preview closed
  row.keystroke = await step(() => type('B'))

  // ---- draft capture: fires 3 s after the last input
  mark = frames.length
  await page.waitForTimeout(4500)
  const capture = frames.slice(mark).find((f) => f.dir === 'out' && f.p.includes('"draft_capture"'))
  if (capture) {
    const reply = frames
      .slice(mark)
      .find((f) => f.dir === 'in' && f.t >= capture.t && f.p.includes('"phx_reply"'))
    row.draftCapture = { bytesOut: capture.p.length, replyMs: reply ? reply.t - capture.t : null }
  } else {
    row.draftCapture = null
  }

  // ---- collapse / expand the first block
  const firstBlock = page.locator('[data-block-uid]').first()
  const toggler = firstBlock.locator('.block-actions label.toggler').first()
  // flipMs: click until the block carries `collapsed`, i.e. what the user sees.
  const baseBlock = page.locator('.base-block').first()
  let flip = 0
  row.collapse = await step(async () => {
    const t = Date.now()
    await toggler.click()
    await expect(baseBlock).toHaveClass(/\bcollapsed\b/)
    flip = Date.now() - t
  })
  row.collapse.flipMs = flip
  row.expand = await step(async () => {
    const t = Date.now()
    await toggler.click()
    await expect(baseBlock).not.toHaveClass(/\bcollapsed\b/)
    flip = Date.now() - t
  })
  row.expand.flipMs = flip

  // ---- open the config modal of a block in the middle of the list
  // `[data-block-uid]` also matches refs, so go through the menu toggles.
  const toggles = page.getByRole('button', { name: 'More actions' })
  const menu = toggles.nth(Math.floor((await toggles.count()) / 2))
  await menu.scrollIntoViewIfNeeded()
  await menu.click()
  const dropdown = page.locator(`[id="${await menu.getAttribute('data-ui-dropdown-toggle')}"]`)
  const configure = dropdown.getByRole('button', { name: 'Configure', exact: true })
  if (await configure.isVisible()) {
    row.configOpen = await step(() => configure.click())
    await page.keyboard.press('Escape')
    await syncLV(page)
  } else {
    await page.keyboard.press('Escape')
    row.configOpen = null
  }
  await page.waitForTimeout(800)

  // ---- live preview: open, keystroke, then bursts
  await page.evaluate(() => window.scrollTo(0, 0))
  row.previewOpen = await step(async () => {
    await toggleLivePreview(page)
    await waitForPreviewReady(page)
  }, 1500)

  await header.click()
  await type('C') // prime with preview open
  await page.waitForTimeout(1500)
  row.keystrokePreview = await step(() => type('D'), 1500)

  // Five block keystrokes 150 ms apart: below the validate debounce, so this
  // is one validate; above it, one per key.
  row.burstBlock = await step(async () => {
    for (const ch of 'VWXYZ') {
      await header.pressSequentially(ch, { delay: 0 })
      await page.waitForTimeout(350)
    }
  }, 2000)

  // Entry-field keystrokes trigger a full preview render each.
  const title = page.getByLabel('Title', { exact: true })
  await title.click()
  await title.press('End')
  row.burstTitle = await step(async () => {
    for (const ch of 'abcde') {
      await title.pressSequentially(ch, { delay: 0 })
      await page.waitForTimeout(350)
    }
  }, 2000)

  // ---- copy the first block to the clipboard
  const firstMenu = page.getByRole('button', { name: 'More actions' }).first()
  await page.evaluate(() => window.scrollTo(0, 0))
  await firstMenu.click()
  const firstDropdown = page.locator(`[id="${await firstMenu.getAttribute('data-ui-dropdown-toggle')}"]`)
  row.copy = await step(() => firstDropdown.getByRole('button', { name: 'Copy to clipboard' }).click(), 2500)
  await page.waitForTimeout(500)

  // ---- open the outline drawer
  await page.locator('.block-field-dropdown-toggle').first().click()
  row.outline = await step(
    () => page.locator('.block-field-dropdown-content button', { hasText: 'Block outline' }).click(),
    2000
  )
  rows.push(row)
  console.log('INTERACTIONS ' + JSON.stringify(row))
}

test.describe('BENCH: block editor interactions', () => {
  test.setTimeout(600000)

  for (const size of ['40', '115']) {
    test(`interactions, ${size} root blocks`, async ({ page }) => {
      await measureEntry(page, size)
    })
  }

  test.afterAll(() => {
    if (rows.length) console.log('\nINTERACTIONS_ALL ' + JSON.stringify(rows, null, 2))
  })
})
