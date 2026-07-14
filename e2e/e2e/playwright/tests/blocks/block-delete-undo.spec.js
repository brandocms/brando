import { test, expect } from '../../test-support/setupAuth'
import { syncLV } from '../../utils'

// Restorable-bin delete/undo.
//
// Deleting a block stashes an op-store bin snapshot (structure + diffs +
// statuses + db ids) before the delete op tears the subtree down; the undo
// toast replays it. The persisted round-trip is the money path: a restored
// persisted block must keep matching its database rows at save (an UPDATE,
// not delete + reinsert), for roots and for nested children.
test.describe('Block delete undo', () => {
  test.describe.configure({ mode: 'serial' })
  test.setTimeout(120000)

  const createPage = async (page, title, uri) => {
    await page.goto('/admin')
    await page.getByRole('link', { name: 'Pages & Sections' }).click()
    await syncLV(page)
    await page.getByRole('link', { name: 'Create page' }).click()
    await syncLV(page)
    await page.getByLabel('Title', { exact: true }).fill(title)
    await page.getByLabel('URI').fill(uri)
  }

  const saveAndReopen = async (page, title) => {
    await page.getByRole('button', { name: 'Save' }).click()
    await expect(page).toHaveURL(/\/admin\/pages$/, { timeout: 30000 })
    await syncLV(page)
    await expect(page.locator('.alert.error')).not.toBeVisible({ timeout: 5000 })

    await page.getByRole('link', { name: `${title} →` }).click()
    await syncLV(page)
  }

  const deleteBlock = async (page, block) => {
    await block.locator('.block-action-dropdown > .block-action').first().click()
    await block
      .locator('.block-action-dropdown-content button', { hasText: 'Delete' })
      .first()
      .click()
    await syncLV(page)
  }

  test('deleted root block restores with content and persists through save + reload', async ({
    page,
  }) => {
    await createPage(page, 'Undo Root Test', 'undo-root-test')

    await page.getByRole('button', { name: 'Add block' }).last().click()
    await page.getByRole('button', { name: '05 LIVE PREVIEW TEST' }).click()
    await page.getByRole('button', { name: 'Styled Header' }).click()
    await syncLV(page)

    const headerText = page.locator('.header-block textarea')
    await headerText.fill('Keep me around')
    await headerText.blur()
    await syncLV(page)

    // persist first — the restored block must re-attach to its EXISTING rows
    await saveAndReopen(page, 'Undo Root Test')
    await expect(page.locator('.header-block textarea')).toHaveValue('Keep me around')

    await deleteBlock(page, page.locator('.entry-block').first())
    await expect(page.locator('.entry-block')).toHaveCount(0)
    await expect(page.getByTestId('block-bin')).toBeVisible()

    await page.getByTestId('block-bin').getByRole('button', { name: 'Undo' }).click()
    await syncLV(page)

    await expect(page.locator('.entry-block')).toHaveCount(1)
    await expect(page.locator('.header-block textarea')).toHaveValue('Keep me around')
    // the bin empties after the restore — the toast goes away
    await expect(page.getByTestId('block-bin')).not.toBeVisible()

    await saveAndReopen(page, 'Undo Root Test')

    await expect(page.locator('.entry-block')).toHaveCount(1)
    await expect(page.locator('.header-block textarea')).toHaveValue('Keep me around')
  })

  test('deleted nested child restores with vars and persists through save + reload', async ({
    page,
  }) => {
    await createPage(page, 'Undo Child Test', 'undo-child-test')

    await page.getByRole('button', { name: 'Add block' }).last().click()
    await page.getByRole('button', { name: 'COPY PASTE TEST' }).click()
    await page.getByRole('button', { name: 'Team Section' }).click()
    await syncLV(page)

    const multiBlock = page.locator('[data-module-multi="true"]')
    await expect(multiBlock).toBeVisible()

    await multiBlock.locator('.block-plus').last().click()
    await page.getByRole('button', { name: 'COPY PASTE TEST' }).click()
    await page.getByRole('button', { name: 'Team Member' }).click()
    await syncLV(page)

    const member = multiBlock.locator('.block-children [data-uid]').first()
    await member.locator('.block-vars').getByLabel('Name').fill('Bob Undo')
    await page.waitForTimeout(400)
    await syncLV(page)
    await member.locator('.block-vars').getByLabel('Role').fill('Restorer')
    await page.waitForTimeout(400)
    await syncLV(page)

    await saveAndReopen(page, 'Undo Child Test')

    const persistedMulti = page.locator('[data-module-multi="true"]')
    const persistedMember = persistedMulti.locator('.block-children [data-uid]').first()
    await expect(persistedMember.locator('.block-vars').getByLabel('Name')).toHaveValue('Bob Undo')

    await deleteBlock(page, persistedMember)
    await expect(persistedMulti.locator('.block-children [data-uid]')).toHaveCount(0)
    await expect(page.getByTestId('block-bin')).toBeVisible()

    await page.getByTestId('block-bin').getByRole('button', { name: 'Undo' }).click()
    await syncLV(page)
    // the child restore re-seeds the whole root via the replace_form cascade —
    // let the remount settle before poking at inputs
    await page.waitForTimeout(750)

    const restoredMember = persistedMulti.locator('.block-children [data-uid]').first()
    await expect(persistedMulti.locator('.block-children [data-uid]')).toHaveCount(1)
    await expect(restoredMember.locator('.block-vars').getByLabel('Name')).toHaveValue('Bob Undo')
    await expect(restoredMember.locator('.block-vars').getByLabel('Role')).toHaveValue('Restorer')

    await saveAndReopen(page, 'Undo Child Test')

    const finalMulti = page.locator('[data-module-multi="true"]')
    const finalMember = finalMulti.locator('.block-children [data-uid]').first()
    await expect(finalMulti.locator('.block-children [data-uid]')).toHaveCount(1)
    await expect(finalMember.locator('.block-vars').getByLabel('Name')).toHaveValue('Bob Undo')
    await expect(finalMember.locator('.block-vars').getByLabel('Role')).toHaveValue('Restorer')
  })
})
