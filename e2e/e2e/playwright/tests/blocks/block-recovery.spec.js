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

  const blockFieldHook = page => page.locator('[phx-hook="Brando.BlockField"]').first()

  const snapshotKeys = page =>
    page.evaluate(() => Object.keys(sessionStorage).filter(k => k.startsWith('brando:block-recovery:')))

  // Save-and-continue on a CREATE: `push_patch(to: update_url)` keeps the same
  // LiveView, so the hook element survives while the entry goes from unsaved to
  // persisted. Returns the id the recovery key is now scoped by.
  //
  // The wait is on the attribute becoming numeric, not on a duration — that
  // transition is the observable this whole area is about, and sleeping before
  // reading it is what `aeb0bce45` removed from these specs.
  const saveAndContinue = async page => {
    await page.getByTestId('split-dropdown-button').click()
    await page.getByRole('button', { name: /Save and continue editing/ }).click()
    await expect(page).toHaveURL(/\/update\//, { timeout: 30000 })
    await syncLV(page)

    const hookEl = blockFieldHook(page)
    await expect(hookEl).toHaveAttribute('data-entry-id', /^\d+$/, { timeout: 15000 })

    return hookEl.getAttribute('data-entry-id')
  }

  const disconnect = async page => {
    await page.evaluate(() => window.liveSocket.disconnect())
    await expect(page.locator('.phx-connected').first()).toBeHidden({ timeout: 15000 })
  }

  const reconnect = async page => {
    await page.evaluate(() => window.liveSocket.connect())
    await syncLV(page)
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

  // C4, closed in Phase 9D — and the plan's stated reason for closing it was
  // wrong about the fact.
  //
  // The finding was that the snapshot key was schema-scoped, so a stale
  // snapshot from entry A could be offered to entry B. The static read closed
  // it on the grounds that the leak "needs the same hook element to survive an
  // entry change, i.e. a push_patch within one LiveView rather than the
  // push_navigate used between entries" — implying no such path existed.
  //
  // One does. Save-and-continue on a CREATE is exactly it: form.ex's
  // `push_patch(to: update_url)` keeps the same LiveView, so the BlockField
  // hook element survives while the entry goes from unsaved to persisted. The
  // `mounted()`-is-a-no-op barrier does not apply on this path.
  //
  // The leak still does not happen, but because of the OTHER barrier — the one
  // C4's own fix shipped. `data-entry-id` (block_field.ex) re-renders with the
  // patch, so `storageKey()` moves forward with the entry instead of serving
  // the `new` bucket to a persisted entry. That is what this pins.
  test('the recovery key follows the entry across save-and-continue', async ({ page }) => {
    await createUnsavedBlock(page, {
      title: 'Key Follows Entry Test',
      uri: 'key-follows-entry-test',
      text: 'Key Follows Header',
    })

    // Unsaved: `@entry.id` is nil, so HEEx omits the attribute entirely and
    // storageKey()'s `this.el.dataset.entryId || 'new'` buckets under `new`.
    const idBeforeSave = await blockFieldHook(page).getAttribute('data-entry-id')
    expect(idBeforeSave ?? '').toBe('')

    // The key moved forward with the entry. If this attribute did NOT re-render
    // on the patch, the persisted entry would go on reading and writing the
    // `new` bucket — which is C4's leak, on the one path that can reach it.
    const entryId = await saveAndContinue(page)

    // And recovery still works after the patch, keyed by the new id: capture on
    // disconnect, read back on reconnect, block intact.
    await disconnect(page)

    const keys = await snapshotKeys(page)
    expect(keys.some(k => k.startsWith(`brando:block-recovery:${entryId}:`))).toBe(true)

    await reconnect(page)

    await expect(page.locator('.entry-block')).toHaveCount(1)
    await expect(page.locator('.header-block textarea')).toHaveValue('Key Follows Header')
  })

  // SUGGESTION 4 from the Phase 9 review, and the reason it was worth taking:
  // C4 is a *cross-entry* leak, so it should be observable as entry A's value
  // turning up in entry B. The test above infers safety from a key prefix,
  // which is one indirection away from the thing the finding names.
  //
  // Two distinct entries, both persisted through save-and-continue, with A's
  // snapshot deliberately left behind in sessionStorage — the shape of a real
  // abandoned edit: the editor disconnects mid-work on A and goes to B in the
  // same tab, so A's snapshot is still sitting there while B mounts and
  // recovers.
  test("one entry never recovers another entry's blocks", async ({ page }) => {
    await createUnsavedBlock(page, {
      title: 'Cross Entry A',
      uri: 'cross-entry-a',
      text: 'Entry A Header',
    })

    const entryA = await saveAndContinue(page)

    // Abandon A while disconnected. Not reconnecting is the point: a successful
    // recovery removes the snapshot, so reconnecting here would clear the very
    // thing that has to still be present when B mounts.
    await disconnect(page)
    const keysAfterA = await snapshotKeys(page)
    expect(keysAfterA.some(k => k.startsWith(`brando:block-recovery:${entryA}:`))).toBe(true)

    // B is reached by a full navigation, so this is a fresh mount with A's
    // snapshot still in the tab's sessionStorage.
    await createUnsavedBlock(page, {
      title: 'Cross Entry B',
      uri: 'cross-entry-b',
      text: 'Entry B Header',
    })

    const entryB = await saveAndContinue(page)
    expect(entryB).not.toBe(entryA)

    await disconnect(page)
    await reconnect(page)

    // The finding, stated as the finding: B recovers B.
    await expect(page.locator('.entry-block')).toHaveCount(1)
    await expect(page.locator('.header-block textarea')).toHaveValue('Entry B Header')

    // A's snapshot is untouched — B recovered from its own bucket rather than
    // consuming A's. Without this, a leak that *also* cleaned up after itself
    // would be indistinguishable from correct behaviour.
    const keysAfterB = await snapshotKeys(page)
    expect(keysAfterB.some(k => k.startsWith(`brando:block-recovery:${entryA}:`))).toBe(true)
  })
})
