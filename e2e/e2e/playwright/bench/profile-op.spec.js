import { test, expect } from '../test-support/setupAuth'
import { syncLV } from '../utils'
import fs from 'fs'
import path from 'path'

// Drives one editor operation inside a window that `e2e/bench/profile_op.exs`
// profiles from inside the BEAM. Payload benchmarks live in
// `block-editor.spec.js` / `tree-triggers.spec.js`; this one exists because
// Phase 3's costs are server time, which the websocket cannot show.
//
//   BENCH_PROFILE=1 BENCH_OP=insert pnpm playwright test \
//     --config bench/playwright.bench.config.js bench/profile-op.spec.js
//
// and, in another shell, while it waits:
//
//   cd e2e/bench && elixir --sname profile --cookie benchcookie profile_op.exs
//
// BENCH_OP: insert | outline | copy   BENCH_ENTRY: 5 | 40 | 115 | nested

const IDS = JSON.parse(fs.readFileSync(path.join(__dirname, 'fixture-ids.json'), 'utf8'))

const FLAG = (name) => path.join(__dirname, `op-${name}.flag`)

const raise = (name) => fs.writeFileSync(FLAG(name), 'x')

const awaitFlag = async (page, name, timeout = 180000) => {
  const deadline = Date.now() + timeout
  while (!fs.existsSync(FLAG(name))) {
    if (Date.now() > deadline) throw new Error(`timed out waiting for ${name} flag`)
    await page.waitForTimeout(100)
  }
}

test.use({ viewport: { width: 1400, height: 1200 }, actionTimeout: 20000 })

const OPS = {
  // Add a block at the end of the root list.
  insert: async (page) => {
    await page.getByRole('button', { name: 'Add block' }).last().click()
    await page.getByRole('button', { name: '05 LIVE PREVIEW TEST' }).click()
    await page.getByRole('button', { name: 'Styled Header' }).click()
    await syncLV(page, 60000)
  },
  // Open the outline drawer: 45 KB of payload, ~1 s of server time.
  outline: async (page) => {
    await page.locator('.block-field-dropdown-toggle').first().click()
    await page
      .locator('.block-field-dropdown-content button', { hasText: 'Block outline' })
      .click()
    await syncLV(page, 60000)
    await page.waitForTimeout(2000)
  },
  // Copy a block: re-renders every block because `clipboard_meta` is threaded
  // to all of them. Lands through a `send_update`, so it needs a settle wait —
  // measured without one, the traffic is billed to whatever runs next.
  copy: async (page) => {
    const block = page.locator('.entry-block [data-block-uid]').first()
    await block.locator('.block-action-dropdown > .block-action').first().click()
    await block
      .locator('.block-action-dropdown-content button', { hasText: 'Copy' })
      .click()
    await syncLV(page, 60000)
    await page.waitForTimeout(2500)
  },
}

// Skipped unless explicitly asked for: this spec blocks on a flag file that
// only `profile_op.exs` raises, so a plain sweep of the bench directory would
// sit here until it times out.
test('BENCH: profile op', async ({ page }) => {
  test.skip(!process.env.BENCH_PROFILE, 'set BENCH_PROFILE=1 and run profile_op.exs alongside it')
  test.setTimeout(600000)

  const op = process.env.BENCH_OP || 'insert'
  const size = process.env.BENCH_ENTRY || '115'
  const entryId = size === 'nested' ? IDS.nested : IDS.flat[size]

  if (!OPS[op]) throw new Error(`unknown BENCH_OP ${op}`)

  await page.goto(`/admin/pages/update/${entryId}`)
  await syncLV(page, 120000)
  await expect(page.locator('[data-block-uid]').first()).toBeVisible({ timeout: 120000 })
  await page.waitForTimeout(2500)

  raise('ready')
  await awaitFlag(page, 'go')

  const t0 = Date.now()
  await OPS[op](page)
  const ms = Date.now() - t0

  raise('done')
  console.log(`PROFILE_OP ${op} @${size} ${ms}ms`)

  // Hold briefly so the profiler detaches before the socket closes.
  await page.waitForTimeout(2000)
})
