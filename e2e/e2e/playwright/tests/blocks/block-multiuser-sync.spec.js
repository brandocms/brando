import { test, expect } from '../../test-support/setupAuth'
import { syncLV } from '../../utils'

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
    await page.waitForTimeout(750)

    return new URL(page.url()).pathname
  }

  // A edits block 1, then clicks into block 2 → block 1's ops ship to B.
  // Real pointer interaction is required — the presence hook listens on
  // focusin/pointerdown; programmatic .focus() does not reach it.
  const editBlockOneAndBlur = async (page) => {
    const blockOne = page.locator('.header-block textarea').nth(0)
    await blockOne.click()
    await blockOne.fill('Alpha edited by A')
    await page.waitForTimeout(600) // debounce flush → op emitted
    await page.locator('.header-block textarea').nth(1).click()
    await page.waitForTimeout(1200) // blur → snapshot ships → B merges
  }

  // B saves WITHOUT having touched anything, then reload must show A's edit
  // (the receiver's save must include shipped edits, not its stale copy)
  const saveAsBAndVerify = async (secondUserPage) => {
    await secondUserPage.getByTestId('split-dropdown-button').click()
    await secondUserPage
      .getByRole('button', { name: /Save and continue editing/ })
      .click()
    await syncLV(secondUserPage)
    await expect(secondUserPage.locator('.alert.error')).not.toBeVisible({ timeout: 5000 })
    await secondUserPage.waitForTimeout(750)

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
    await page.waitForTimeout(600) // debounce flush → op emitted

    // blur to something OUTSIDE the blocks — the old trigger only shipped
    // when ANOTHER block got focused
    await page.getByLabel('Title', { exact: true }).click()
    await page.waitForTimeout(1500) // focus settle (400ms) → ship → B applies

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
    await page.waitForTimeout(600)
    await page.getByLabel('Title', { exact: true }).click()
    await page.waitForTimeout(1500)

    // B joins AFTER the edit — its join sync request must replay A's state
    await secondUserPage.goto(entryUrl)
    await syncLV(secondUserPage)

    await expect(secondUserPage.locator('.header-block textarea').nth(0)).toHaveValue(
      'Alpha before B joined',
      { timeout: 5000 }
    )
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
    await page.getByRole('button', { name: 'Team Member' }).click()
    await syncLV(page)

    const member = multiBlock.locator('.block-children [data-uid]').first()
    await member.locator('.block-vars').getByLabel('Name').fill('Doomed Member')
    await page.waitForTimeout(400)
    await syncLV(page)

    await page.getByTestId('split-dropdown-button').click()
    await page.getByRole('button', { name: /Save and continue editing/ }).click()
    await expect(page).toHaveURL(/\/update\//, { timeout: 30000 })
    await syncLV(page)
    await page.waitForTimeout(750)

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
