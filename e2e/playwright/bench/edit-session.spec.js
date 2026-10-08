import { test, expect } from '../test-support/setupAuth'
import { syncLV } from '../utils'
import fs from 'fs'
import path from 'path'

// Edit session benchmark (#2992). NOT part of the regression suite.
//
//   cd e2e/playwright
//   pnpm playwright test --config bench/playwright.bench.config.js bench/edit-session.spec.js
//
// Needs the large fixtures (see bench/README.md). Prints `ES_BENCH` rows:
//
// * open: time from navigation until every root block is on screen and the
//   LiveView is idle, three fresh opens per entry;
// * typing: bytes in and out for one debounced keystroke on the typist;
// * observer: bytes a second editor on the same entry receives for that
//   keystroke, and for the blur that follows it;
// * window: the keystroke's start and end (ms since the epoch), to match
//   server-side LiveView telemetry against.

const IDS = JSON.parse(fs.readFileSync(path.join(__dirname, 'fixture-ids.json'), 'utf8'))

test.use({ viewport: { width: 1400, height: 1200 }, actionTimeout: 20000 })

const recorder = page => {
  const frames = []
  page.on('websocket', ws => {
    ws.on('framesent', d => typeof d.payload === 'string' && frames.push({ dir: 'out', n: d.payload.length, p: d.payload }))
    ws.on('framereceived', d => typeof d.payload === 'string' && frames.push({ dir: 'in', n: d.payload.length, p: d.payload }))
  })

  const mark = () => frames.length
  const since = m => {
    const slice = frames.slice(m).filter(f => !f.p.includes('"phoenix"'))
    const sum = dir => slice.filter(f => f.dir === dir).reduce((a, f) => a + f.n, 0)
    return { out: sum('out'), in: sum('in'), frames: slice.length }
  }
  return { mark, since }
}

const open = async (page, id) => {
  const t0 = Date.now()
  await page.goto(`/admin/pages/update/${id}`)
  await syncLV(page, 120000)
  await expect(page.locator('[data-block-uid]').first()).toBeVisible({ timeout: 120000 })
  await syncLV(page, 120000)
  return Date.now() - t0
}

const textInput = page =>
  page.locator('.header-block textarea').first()

for (const [label, id] of [['flat-115', IDS.flat['115']], ['nested', IDS.nested]]) {
  test(`edit session bench ${label}`, async ({ page, secondUserPage }) => {
    test.setTimeout(600000)
    const row = { entry: label, open: [] }

    const typist = recorder(page)
    const observer = recorder(secondUserPage)
    for (let i = 0; i < 3; i++) row.open.push(await open(page, id))

    await open(secondUserPage, id)
    await page.waitForTimeout(1500)

    const hasHeader = (await page.locator('.header-block textarea').count()) > 0
    const input = hasHeader ? textInput(page) : page.locator('[data-block-uid] input[type="text"]:visible').first()
    await input.click()
    await page.waitForTimeout(800)
    await input.pressSequentially('A', { delay: 20 })
    await page.waitForTimeout(1400)
    await syncLV(page, 60000)
    await page.waitForTimeout(800)

    let t = typist.mark()
    let o = observer.mark()
    const from = Date.now()
    await input.pressSequentially('B', { delay: 20 })
    await page.waitForTimeout(1400)
    await syncLV(page, 60000)
    await page.waitForTimeout(600)
    row.typing = typist.since(t)
    row.window = [from, Date.now()]
    row.observerKeystroke = observer.since(o)

    o = observer.mark()
    await page.getByLabel('Title', { exact: true }).click()
    await page.waitForTimeout(1500)
    row.observerBlur = observer.since(o)

    console.log('ES_BENCH ' + JSON.stringify(row))
  })
}
