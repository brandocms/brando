import { test, expect } from '../../test-support/setupAuth'
import { syncLV, goOffline, goOnline } from '../../utils'

test.describe('Block Recovery', () => {
  test.setTimeout(90000)

  // Create page → add one Styled Header → give it a known value.
  // Nothing here is ever saved, which is the point: a never-persisted root block
  // is the one thing LiveView's own form recovery structurally cannot restore,
  // and therefore the only thing `BlockField`'s sessionStorage mechanism is for.
  const createUnsavedBlock = async (page, { title, uri, text }) => {
    await page.goto('/admin')
    await page.getByRole('link', { name: 'Pages & Sections' }).click()
    await syncLV(page)

    await page.getByRole('link', { name: 'Create page' }).click()
    await syncLV(page)

    await page.getByLabel('Title', { exact: true }).fill(title)
    await page.getByLabel('URI').fill(uri)

    await page.getByRole('button', { name: 'Add block' }).click()
    await page.getByRole('button', { name: '05 LIVE PREVIEW TEST' }).click()
    await page.getByRole('button', { name: 'Styled Header' }).click()
    await syncLV(page)

    const headerTextarea = page.locator('.header-block textarea')
    await headerTextarea.fill(text)
    await syncLV(page)

    await expect(page.locator('.entry-block')).toHaveCount(1)
  }

  test('blocks recover after disconnect/reconnect without errors', async ({ page }) => {
    await createUnsavedBlock(page, {
      title: 'Block Recovery Test Page',
      uri: 'block-recovery-test',
      text: 'Recovery Test Header',
    })

    // A cooperative disconnect: the client is told to stop. Waiting for
    // `.phx-connected` to go rather than sleeping 500ms means this cannot pass
    // early on a fast machine or fail late on a slow one.
    await page.evaluate(() => window.liveSocket.disconnect())
    await expect(page.locator('.phx-connected').first()).toBeHidden({ timeout: 15000 })

    await page.evaluate(() => window.liveSocket.connect())
    await syncLV(page)

    await expect(page.locator('.entry-block')).toHaveCount(1)
    await expect(page.locator('.header-block textarea')).toHaveValue('Recovery Test Header')
  })

  // The same journey with the connection taken away instead of handed back —
  // and it does NOT recover. This is the gap Phase 4 suspected the cooperative
  // test was hiding, now measured.
  //
  // What actually happens, from the probe that produced this test:
  //
  //   * `disconnected()` fires and the snapshot IS written correctly — the root
  //     uid and its form are both in sessionStorage.
  //   * when the network returns, LiveView cannot rejoin the view it lost, so it
  //     does a **full page reload** rather than a rejoin.
  //   * a reloaded page runs `mounted()`, which is deliberately a no-op
  //     ("No recovery on fresh mount"). `reconnected()` never fires, so the
  //     snapshot is never read. It sits there until its 1h TTL expires.
  //
  // So block recovery today covers `liveSocket.disconnect()` → `connect()`, a
  // path only a test or the dev console takes, and not the connection loss it
  // was written for.
  //
  // **This is not fixable by moving recovery into `mounted()`**, which is the
  // obvious patch. Unsaved entries all share the `new` storage bucket (C4), so
  // recovering on mount would replay one abandoned create form's blocks into the
  // next one — exactly what the "stale sessionStorage" test below forbids. A real
  // fix needs an identity that survives a reload but does not collide across
  // create forms, which is a design change, not a line edit.
  //
  // Asserted as-is so the gap is visible and a future fix flips this test rather
  // than being invisible.
  test('a real network partition does NOT recover — snapshot is written, never read', async ({
    page,
  }) => {
    await createUnsavedBlock(page, {
      title: 'Block Partition Test Page',
      uri: 'block-partition-test',
      text: 'Partition Test Header',
    })

    await goOffline(page)

    // The capture half works: the snapshot exists and holds the unsaved root.
    const snapshot = await page.evaluate(() => {
      const key = Object.keys(sessionStorage).find(k => k.startsWith('brando:block-recovery:'))
      return key ? { key, ...JSON.parse(sessionStorage.getItem(key)) } : null
    })

    expect(snapshot).not.toBeNull()
    expect(snapshot.rootUids).toHaveLength(1)
    expect(Object.keys(snapshot.forms)).toEqual([`entry_block_form-${snapshot.rootUids[0]}`])

    await goOnline(page)

    // The replay half does not. LiveView reloaded the page instead of rejoining,
    // so the form came back empty and the snapshot was left unread.
    await expect(page.locator('.entry-block')).toHaveCount(0)
    await expect(page.getByLabel('Title', { exact: true })).toHaveValue('')

    const stillStored = await page.evaluate(
      key => sessionStorage.getItem(key) !== null,
      snapshot.key
    )
    expect(stillStored).toBe(true)
  })

  // Phase 4 asked for a "positive sessionStorage-recovery assertion via hard
  // page.reload()". **There is no such thing, and that is deliberate**: the hook
  // captures in `disconnected()` and recovers in `reconnected()`, while
  // `mounted()` is an explicit no-op ("No recovery on fresh mount"). A reload
  // tears the page down without a disconnect and brings it back as a fresh
  // mount, so neither half runs.
  //
  // What is worth pinning is the hazard that follows from it. sessionStorage
  // survives a reload within the tab, so the snapshot is still sitting there on
  // the new page. If recovery ever moved to `mounted()`, blocks the user
  // abandoned would resurrect themselves on an unrelated page. The contract is
  // that a reload starts clean.
  test('a hard reload starts clean and does not replay a stale snapshot', async ({ page }) => {
    await createUnsavedBlock(page, {
      title: 'Block Reload Test Page',
      uri: 'block-reload-test',
      text: 'Reload Test Header',
    })

    // Force a snapshot to exist, then reload without ever reconnecting — the
    // snapshot outlives the page it was taken on.
    await page.evaluate(() => window.liveSocket.disconnect())
    await expect(page.locator('.phx-connected').first()).toBeHidden({ timeout: 15000 })

    const snapshotKeys = await page.evaluate(() =>
      Object.keys(sessionStorage).filter(k => k.startsWith('brando:block-recovery:'))
    )
    expect(snapshotKeys.length).toBeGreaterThan(0)

    await page.reload()
    await syncLV(page)

    // The snapshot survived the reload...
    const keysAfterReload = await page.evaluate(() =>
      Object.keys(sessionStorage).filter(k => k.startsWith('brando:block-recovery:'))
    )
    expect(keysAfterReload).toEqual(snapshotKeys)

    // ...and was not replayed. A create form reloads to an empty create form:
    // the unsaved block is gone, which is the honest outcome, and no block from
    // the previous page is injected into this one.
    await expect(page.locator('.entry-block')).toHaveCount(0)
  })

  test('stale sessionStorage does not trigger recovery on fresh navigation', async ({ page }) => {
    await createUnsavedBlock(page, {
      title: 'Stale Recovery Test Page',
      uri: 'stale-recovery-test',
      text: 'Stale Test Header',
    })

    // Simulate stale sessionStorage by disconnecting (which captures form data)
    // then navigating away without reconnecting
    await page.evaluate(() => window.liveSocket.disconnect())
    await expect(page.locator('.phx-connected').first()).toBeHidden({ timeout: 15000 })

    // Navigate away and back — this is a fresh mount, not a reconnect
    await page.evaluate(() => window.liveSocket.connect())
    await page.goto('/admin')
    await syncLV(page)

    await page.getByRole('link', { name: 'Pages & Sections' }).click()
    await syncLV(page)

    await page.getByRole('link', { name: 'Create page' }).click()
    await syncLV(page)

    await page.getByLabel('Title', { exact: true }).fill('Fresh Page After Stale')
    await page.getByLabel('URI').fill('fresh-after-stale')

    // Add a block — this should work without any "already associated" errors
    await page.getByRole('button', { name: 'Add block' }).click()
    await page.getByRole('button', { name: '05 LIVE PREVIEW TEST' }).click()
    await page.getByRole('button', { name: 'Styled Header' }).click()
    await syncLV(page)

    // Verify the block rendered correctly (no crash)
    await expect(page.locator('.entry-block')).toHaveCount(1)
    await expect(page.locator('.header-block textarea')).toBeVisible()
  })
})
