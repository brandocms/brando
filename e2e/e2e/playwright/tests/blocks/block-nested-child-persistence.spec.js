import { test, expect } from '../../test-support/setupAuth'
import { syncLV } from '../../utils'

// Save → reload persistence for NESTED child blocks (multi/container children).
//
// Every other persistence spec operates on root blocks only — a gap that hid
// an entire chain of save-path bugs: the materialized save cast dropped all
// `children` params (child edits never persisted), new-child inserts crashed
// once that was fixed, and deleting a parent's last child never reached the
// database. These specs drive the child flows end-to-end through the UI:
// insert child → edit child vars → save → reload → edit again → delete.
test.describe('Nested child block persistence', () => {
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

  const addTeamSectionWithMember = async (page, name, role) => {
    await page.getByRole('button', { name: 'Add block' }).last().click()
    await page.getByRole('button', { name: 'COPY PASTE TEST' }).click()
    await page.getByRole('button', { name: 'Team Section' }).click()
    await syncLV(page)

    const multiBlock = page.locator('[data-module-multi="true"]')
    await expect(multiBlock).toBeVisible()
    await expect(multiBlock.locator('.block-liquex-preview .split_content')).toHaveCount(1)

    await multiBlock.locator('.block-plus').last().click()
    await page.getByRole('button', { name: 'COPY PASTE TEST' }).click()
    await page.getByRole('button', { name: /^Team Member\b/ }).click()
    await syncLV(page)

    const memberBlock = multiBlock.locator('.block-children [data-uid]').first()
    await memberBlock.locator('.block-vars').getByLabel('Name').fill(name)
    await page.waitForTimeout(400)
    await syncLV(page)
    await memberBlock.locator('.block-vars').getByLabel('Role').fill(role)
    await page.waitForTimeout(400)
    await syncLV(page)

    return multiBlock
  }

  const saveAndReopen = async (page, title) => {
    await page.getByRole('button', { name: 'Save' }).click()
    await expect(page).toHaveURL(/\/admin\/pages$/, { timeout: 30000 })
    await syncLV(page)
    await expect(page.locator('.alert.error')).not.toBeVisible({ timeout: 5000 })

    await page.getByRole('link', { name: `${title} →` }).click()
    await syncLV(page)
  }

  test('child insert + var edits persist through save + reload, then edit + save again', async ({
    page,
  }) => {
    await createPage(page, 'Nested Child Test', 'nested-child-test')
    await addTeamSectionWithMember(page, 'Alice Smith', 'Lead Engineer')

    await saveAndReopen(page, 'Nested Child Test')

    // the child row and its var values must have reached the database
    const multiBlock = page.locator('[data-module-multi="true"]')
    const member = multiBlock.locator('.block-children [data-uid]').first()
    await expect(multiBlock.locator('.block-children [data-uid]')).toHaveCount(1)
    await expect(member.locator('.block-vars').getByLabel('Name')).toHaveValue('Alice Smith')
    await expect(member.locator('.block-vars').getByLabel('Role')).toHaveValue('Lead Engineer')

    // edit the now-PERSISTED child (an UPDATE, not delete+reinsert) and
    // round-trip again — this is the flow that silently lost edits
    await member.locator('.block-vars').getByLabel('Role').fill('Principal Engineer')
    await page.waitForTimeout(400)
    await syncLV(page)

    await saveAndReopen(page, 'Nested Child Test')

    const memberAfter = page
      .locator('[data-module-multi="true"]')
      .locator('.block-children [data-uid]')
      .first()

    await expect(memberAfter.locator('.block-vars').getByLabel('Name')).toHaveValue('Alice Smith')
    await expect(memberAfter.locator('.block-vars').getByLabel('Role')).toHaveValue(
      'Principal Engineer'
    )
  })

  test('deleting a persisted last child survives save + reload', async ({ page }) => {
    await createPage(page, 'Nested Delete Test', 'nested-delete-test')
    await addTeamSectionWithMember(page, 'Bob Jones', 'Designer')

    await saveAndReopen(page, 'Nested Delete Test')

    const multiBlock = page.locator('[data-module-multi="true"]')
    const member = multiBlock.locator('.block-children [data-uid]').first()
    await expect(member.locator('.block-vars').getByLabel('Name')).toHaveValue('Bob Jones')

    // delete the only child via its action dropdown — the parent's children
    // list becomes empty, which must still express the deletion at save
    await member.locator('.block-action-dropdown > .block-action').click()
    await member.locator('.block-action-dropdown-content button', { hasText: 'Delete' }).click()
    await syncLV(page)
    await expect(multiBlock.locator('.block-children [data-uid]')).toHaveCount(0)

    await saveAndReopen(page, 'Nested Delete Test')

    await expect(page.locator('[data-module-multi="true"]')).toBeVisible()
    await expect(
      page.locator('[data-module-multi="true"]').locator('.block-children [data-uid]')
    ).toHaveCount(0)
  })
})
