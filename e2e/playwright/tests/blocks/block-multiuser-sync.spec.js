import { test, expect } from '../../test-support/setupAuth'
import { syncLV, awaitBlockDebounce, awaitBlockShip } from '../../utils'

// Multi-user block sync: two logged-in users (two browser contexts sharing
// one sandbox session) editing the same entry.
//
// Guarantees under test:
// * blur ships: A's edit reaches B on plain blur — no other block needs
//   focusing (the settle-ship on focusout), and B SEES it (header textareas
//   are no longer phx-update="ignore")
// * B's untouched save includes A's shipped edit instead of clobbering it
// * late joiners get unsaved state on mount (join sync request/replay)
// * child structural ops (delete) ship immediately, no blur needed
test.describe('Multi-user block sync', () => {
  test.setTimeout(120000)

  const createEntryWithTwoHeaders = async (page, title, uri) => {
    await page.goto('/admin')
    await page.getByRole('link', { name: 'Pages & Sections' }).click()
    await syncLV(page)
    await page.getByRole('link', { name: 'Create page' }).click()
    await syncLV(page)
    await page.getByLabel('Title', { exact: true }).fill(title)
    await page.getByLabel('URI').fill(uri)

    const addHeader = async (textIndex, text) => {
      await page.getByRole('button', { name: 'Add block' }).last().click()
      await page.getByRole('button', { name: '05 LIVE PREVIEW TEST' }).click()
      await page.getByRole('button', { name: 'Styled Header' }).click()
      await syncLV(page)
      const ta = page.locator('.header-block textarea').nth(textIndex)
      await ta.fill(text)
      await ta.blur()
      await syncLV(page)
    }

    await addHeader(0, 'Alpha')
    await addHeader(1, 'Beta')

    // save and continue editing (A stays on the patched create form)
    await page.getByTestId('split-dropdown-button').click()
    await page.getByRole('button', { name: /Save and continue editing/ }).click()
    await expect(page).toHaveURL(/\/update\//, { timeout: 30000 })
    await syncLV(page)
    // The block editor is deferred a tick past the entry load, so `syncLV` alone
    // returns while the blocks are still a loader shell. Wait for the blocks
    // themselves rather than for 750ms.
    await expect(page.locator('.header-block textarea').nth(1)).toHaveValue('Beta', {
      timeout: 15000,
    })

    return new URL(page.url()).pathname
  }

  // A edits block 1, then clicks into block 2 → block 1's ops ship to B.
  // Real pointer interaction is required — the presence hook listens on
  // focusin/pointerdown; programmatic .focus() does not reach it.
  const editBlockOneAndBlur = async (page) => {
    const blockOne = page.locator('.header-block textarea').nth(0)
    await blockOne.click()
    await blockOne.fill('Alpha edited by A')
    await awaitBlockDebounce(page)
    await page.locator('.header-block textarea').nth(1).click()
    await awaitBlockShip(page)
  }

  // B saves WITHOUT having touched anything, then reload must show A's edit
  // (the receiver's save must include shipped edits, not its stale copy)
  const saveAsBAndVerify = async (secondUserPage) => {
    // Wait for B to have RECEIVED the ship before saving. `awaitBlockShip` in
    // `editBlockOneAndBlur` only establishes that A *sent* it; the broadcast,
    // B's server-side apply and B's diff are all still in flight at that point.
    // Without this, B could save its stale copy, the assertion below would fail,
    // and the failure would read as "the receiver clobbered A's edit" — the
    // exact bug this test exists to catch — when the real cause was the test
    // saving too early. A spec that reports the right failure for the wrong
    // reason is worse than a flaky one.
    //
    // Removing `waitForTimeout` did not make this correct; it made the window
    // narrower. This closes it on an event instead: the value in B's DOM.
    await expect(secondUserPage.locator('.header-block textarea').nth(0)).toHaveValue(
      'Alpha edited by A',
      { timeout: 15000 }
    )

    await secondUserPage.getByTestId('split-dropdown-button').click()
    await secondUserPage
      .getByRole('button', { name: /Save and continue editing/ })
      .click()
    await syncLV(secondUserPage)
    await expect(secondUserPage.locator('.alert.error')).not.toBeVisible({ timeout: 5000 })
    // The save redirects/patches; wait for that rather than for 750ms.
    await expect(secondUserPage).toHaveURL(/\/update\//, { timeout: 30000 })

    await secondUserPage.reload()
    await syncLV(secondUserPage)
    await expect(secondUserPage.locator('.header-block textarea').nth(0)).toHaveValue(
      'Alpha edited by A'
    )
    await expect(secondUserPage.locator('.header-block textarea').nth(1)).toHaveValue('Beta')
  }

  test("user B's save preserves user A's shipped block edit", async ({
    page,
    secondUserPage,
  }) => {
    const entryUrl = await createEntryWithTwoHeaders(page, 'Multiuser Sync Test', 'multiuser-sync-test')

    // A on a fresh mount of the update route
    await page.goto(entryUrl)
    await syncLV(page)
    await expect(page.locator('.header-block textarea').nth(0)).toHaveValue('Alpha')

    await secondUserPage.goto(entryUrl)
    await syncLV(secondUserPage)
    await expect(secondUserPage.locator('.header-block textarea').nth(0)).toHaveValue('Alpha')

    await editBlockOneAndBlur(page)
    await saveAsBAndVerify(secondUserPage)
  })

  test('sync is armed right after create + save-and-continue (no reload)', async ({
    page,
    secondUserPage,
  }) => {
    // A stays on the PATCHED create form — entry scope (entry_id + topics)
    // must arm via handle_params on the push_patch, without a full reload
    const entryUrl = await createEntryWithTwoHeaders(
      page,
      'Multiuser Fresh Test',
      'multiuser-fresh-test'
    )

    await secondUserPage.goto(entryUrl)
    await syncLV(secondUserPage)
    await expect(secondUserPage.locator('.header-block textarea').nth(0)).toHaveValue('Alpha')

    await editBlockOneAndBlur(page)
    await saveAsBAndVerify(secondUserPage)
  })

  test("A's plain blur ships the edit and B SEES it — no other block focused", async ({
    page,
    secondUserPage,
  }) => {
    const entryUrl = await createEntryWithTwoHeaders(page, 'Multiuser Blur Test', 'multiuser-blur-test')

    await page.goto(entryUrl)
    await syncLV(page)
    await secondUserPage.goto(entryUrl)
    await syncLV(secondUserPage)
    await expect(secondUserPage.locator('.header-block textarea').nth(0)).toHaveValue('Alpha')

    const ta = page.locator('.header-block textarea').nth(0)
    await ta.click()
    await ta.fill('Alpha blurred by A')
    await awaitBlockDebounce(page)

    // blur to something OUTSIDE the blocks — the old trigger only shipped
    // when ANOTHER block got focused
    await page.getByLabel('Title', { exact: true }).click()
    await awaitBlockShip(page)

    await expect(secondUserPage.locator('.header-block textarea').nth(0)).toHaveValue(
      'Alpha blurred by A',
      { timeout: 5000 }
    )
  })

  test('late joiner receives unsaved edits on mount', async ({ page, secondUserPage }) => {
    const entryUrl = await createEntryWithTwoHeaders(
      page,
      'Multiuser Late Join',
      'multiuser-late-join'
    )

    await page.goto(entryUrl)
    await syncLV(page)

    const ta = page.locator('.header-block textarea').nth(0)
    await ta.click()
    await ta.fill('Alpha before B joined')
    await awaitBlockDebounce(page)
    await page.getByLabel('Title', { exact: true }).click()
    await awaitBlockShip(page)

    // B joins AFTER the edit — its join sync request must replay A's state
    await secondUserPage.goto(entryUrl)
    await syncLV(secondUserPage)

    await expect(secondUserPage.locator('.header-block textarea').nth(0)).toHaveValue(
      'Alpha before B joined',
      { timeout: 5000 }
    )
  })

  // A page with one Rich Text Article (TipTap text ref), persisted via
  // save-and-continue so A stays on the armed update form.
  const createEntryWithTextBlock = async (page, title, uri) => {
    await page.goto('/admin')
    await page.getByRole('link', { name: 'Pages & Sections' }).click()
    await syncLV(page)
    await page.getByRole('link', { name: 'Create page' }).click()
    await syncLV(page)
    await page.getByLabel('Title', { exact: true }).fill(title)
    await page.getByLabel('URI').fill(uri)

    await page.getByRole('button', { name: 'Add block' }).last().click()
    await page.getByRole('button', { name: '05 LIVE PREVIEW TEST' }).click()
    await page.getByRole('button', { name: 'Rich Text Article' }).click()
    await syncLV(page)

    await page.getByTestId('split-dropdown-button').click()
    await page.getByRole('button', { name: /Save and continue editing/ }).click()
    await expect(page).toHaveURL(/\/update\//, { timeout: 30000 })
    await syncLV(page)
    await expect(
      page.locator('[data-tiptap-type="block"] .tiptap-target [contenteditable]').first()
    ).toBeVisible({ timeout: 15000 })

    return new URL(page.url()).pathname
  }

  const editTipTap = async (page, text) => {
    const editor = page.locator('[data-tiptap-type="block"] .tiptap-target [contenteditable]').first()
    await editor.click()
    await page.keyboard.press('ControlOrMeta+a')
    await page.keyboard.type(text)
    await awaitBlockDebounce(page) // tiptap → hidden input mirror → debounce flush → op
  }

  test("A's tiptap edit is VISIBLE for a connected B after plain blur", async ({
    page,
    secondUserPage,
  }) => {
    const entryUrl = await createEntryWithTextBlock(page, 'Multiuser TipTap Live', 'multiuser-tiptap-live')

    await page.goto(entryUrl)
    await syncLV(page)
    await secondUserPage.goto(entryUrl)
    await syncLV(secondUserPage)
    await expect(secondUserPage.locator('[data-tiptap-type="block"] .tiptap-target [contenteditable]').first()).toContainText(
      'Article content goes here'
    )

    await editTipTap(page, 'Rewritten live by A')
    // stage 1: A's editor mirrored into A's hidden input (op committed)
    await expect(page.locator('[data-tiptap-type="block"] .tiptap-text').first()).toHaveValue(/Rewritten live by A/, {
      timeout: 3000,
    })

    // blur to something outside the blocks
    await page.getByLabel('Title', { exact: true }).click()
    await awaitBlockShip(page) // settle → ship → B applies + remounts

    // stage 2: the ship reached B's store and patched B's hidden input
    await expect(secondUserPage.locator('[data-tiptap-type="block"] .tiptap-text').first()).toHaveValue(
      /Rewritten live by A/,
      { timeout: 5000 }
    )

    // stage 3: B's editor re-booted with the new content (visible)
    await expect(secondUserPage.locator('[data-tiptap-type="block"] .tiptap-target [contenteditable]').first()).toContainText(
      'Rewritten live by A',
      { timeout: 5000 }
    )
  })

  test('late joiner receives tiptap content AND entry field changes', async ({
    page,
    secondUserPage,
  }) => {
    const entryUrl = await createEntryWithTextBlock(page, 'Multiuser TipTap Late', 'multiuser-tiptap-late')

    await page.goto(entryUrl)
    await syncLV(page)

    await editTipTap(page, 'Written before B joined')
    // edit an ENTRY FIELD too (field sync, not block sync)
    const title = page.getByLabel('Title', { exact: true })
    await title.click()
    await title.fill('Title changed by A')
    // focus another field so the field-change ships / block settle fires
    await page.getByLabel('URI').click()
    await awaitBlockShip(page)

    await secondUserPage.goto(entryUrl)
    await syncLV(secondUserPage)

    await expect(secondUserPage.locator('[data-tiptap-type="block"] .tiptap-target [contenteditable]').first()).toContainText(
      'Written before B joined',
      { timeout: 5000 }
    )
    await expect(secondUserPage.getByLabel('Title', { exact: true })).toHaveValue(
      'Title changed by A',
      { timeout: 5000 }
    )
  })

  test('block locks appear for late joiners, survive remote applies, clear on blur', async ({
    page,
    secondUserPage,
  }) => {
    const entryUrl = await createEntryWithTwoHeaders(page, 'Multiuser Lock Test', 'multiuser-lock-test')

    await page.goto(entryUrl)
    await syncLV(page)

    // A focuses block 1 and stays in it
    const ta = page.locator('.header-block textarea').nth(0)
    await ta.click()

    // B joins late — A's focus replays via the join sync request, so the
    // block must show locked WITHOUT waiting for A's next focus event
    await secondUserPage.goto(entryUrl)
    await syncLV(secondUserPage)
    const bBlockOne = secondUserPage.locator('.entry-block').nth(0).locator('.block').first()
    await expect(bBlockOne).toHaveClass(/block-locked/, { timeout: 5000 })

    // A edits, then clicks elsewhere INSIDE the same block — content ships
    // (still_inside), B's locked block re-renders from the applied snapshot.
    // The patch resets classes to server truth; the lock must be re-asserted,
    // not flicker away (this was the flaky-lock class of bugs).
    await ta.fill('Alpha locked edit')
    await awaitBlockDebounce(page)
    await page.locator('.entry-block').nth(0).locator('.block-description').first().click()
    await awaitBlockShip(page)

    await expect(secondUserPage.locator('.header-block textarea').nth(0)).toHaveValue(
      'Alpha locked edit',
      { timeout: 5000 }
    )
    await expect(bBlockOne).toHaveClass(/block-locked/)

    // A leaves the block entirely → the lock must clear on B
    await page.getByLabel('Title', { exact: true }).click()
    await expect(bBlockOne).not.toHaveClass(/block-locked/, { timeout: 5000 })
  })

  test('field locks appear for late joiners and survive form patches', async ({
    page,
    secondUserPage,
  }) => {
    const entryUrl = await createEntryWithTwoHeaders(page, 'Multiuser Field Lock', 'multiuser-field-lock')

    await page.goto(entryUrl)
    await syncLV(page)

    // A focuses the Title entry field and stays there
    await page.getByLabel('Title', { exact: true }).click()

    // B joins late — A's active field replays via the join sync request
    await secondUserPage.goto(entryUrl)
    await syncLV(secondUserPage)
    const lockedWrapper = secondUserPage.locator('.field-wrapper.field-locked')
    await expect(lockedWrapper).toHaveCount(1, { timeout: 5000 })
    await expect(lockedWrapper.getByLabel('Title', { exact: true })).toBeAttached()

    // B edits another field — every keystroke re-renders B's form; the
    // sticky lock class must survive the patches (a plain classList.add
    // used to get wiped here)
    const uri = secondUserPage.getByLabel('URI')
    await uri.click()
    await uri.fill('multiuser-field-lock-x')
    await awaitBlockDebounce(secondUserPage)

    await expect(secondUserPage.locator('.field-wrapper.field-locked')).toHaveCount(1)
    await expect(lockedWrapper.getByLabel('Title', { exact: true })).toBeAttached()
  })

  test("A's child delete syncs to B immediately, no blur needed", async ({
    page,
    secondUserPage,
  }) => {
    // build a Team Section with one member and persist it
    await page.goto('/admin')
    await page.getByRole('link', { name: 'Pages & Sections' }).click()
    await syncLV(page)
    await page.getByRole('link', { name: 'Create page' }).click()
    await syncLV(page)
    await page.getByLabel('Title', { exact: true }).fill('Multiuser Child Delete')
    await page.getByLabel('URI').fill('multiuser-child-delete')

    await page.getByRole('button', { name: 'Add block' }).last().click()
    await page.getByRole('button', { name: 'COPY PASTE TEST' }).click()
    await page.getByRole('button', { name: 'Team Section' }).click()
    await syncLV(page)

    const multiBlock = page.locator('[data-module-multi="true"]')
    await multiBlock.locator('.block-plus').last().click()
    await page.getByRole('button', { name: 'COPY PASTE TEST' }).click()
    await page.getByRole('button', { name: /^Team Member\b/ }).click()
    await syncLV(page)

    const member = multiBlock.locator('.block-children [data-uid]').first()
    await member.locator('.block-vars').getByLabel('Name').fill('Doomed Member')
    await awaitBlockDebounce(page)

    await page.getByTestId('split-dropdown-button').click()
    await page.getByRole('button', { name: /Save and continue editing/ }).click()
    await expect(page).toHaveURL(/\/update\//, { timeout: 30000 })
    await syncLV(page)
    await expect(
      page.locator('[data-module-multi="true"] .block-children [data-uid]').first()
    ).toBeVisible({ timeout: 15000 })

    const entryUrl = new URL(page.url()).pathname

    await secondUserPage.goto(entryUrl)
    await syncLV(secondUserPage)
    const bChildren = secondUserPage
      .locator('[data-module-multi="true"]')
      .locator('.block-children [data-uid]')
    await expect(bChildren).toHaveCount(1)

    // A deletes the child — the structural op must ship its root's subtree
    // (with the delete tombstone) right away
    const aMember = page.locator('[data-module-multi="true"]').locator('.block-children [data-uid]').first()
    await aMember.locator('.block-action-dropdown > .block-action').first().click()
    await aMember
      .locator('.block-action-dropdown-content button', { hasText: 'Delete' })
      .first()
      .click()
    await syncLV(page)

    await expect(bChildren).toHaveCount(0, { timeout: 5000 })
  })
})
