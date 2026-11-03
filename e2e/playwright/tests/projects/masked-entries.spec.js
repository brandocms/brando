import { test, expect } from '../../test-support/setupAuth'
import { syncLV } from '../../utils'

// With group authorization, an `:entries` input shows a selected entry the
// editor may not read as a masked row: without its title, and with its
// hidden inputs, so a save keeps the link. The fixture's editor
// (`secondUserPage`) may edit projects and clients and read no pages. A
// project's related entries, and the related entries of a client's row
// (form `:related_rows`), name a page and a project.
test.skip(process.env.BRANDO_AUTHORIZATION_MODE !== 'groups', 'Requires explicit group mode')

test.use({ viewport: { width: 1440, height: 1000 } })

const HIDDEN = 'Staff handbook'

async function fixtures(page) {
  const response = await page.request.post('/e2e/masked-entries-fixtures')
  expect(response.ok(), await response.text()).toBeTruthy()
  return response.json()
}

// The rows of an entries input, the masked one first
async function expectMasked(page, rows, count) {
  await expect(rows).toHaveCount(count)
  await expect(rows.nth(0)).toHaveClass(/\bmasked\b/)
  await expect(rows.nth(0).locator('input[type=hidden][name$="[identifier_id]"]')).toHaveCount(1)
  await expect(rows.nth(1)).toContainText('The garden rooms')
  await expect(page.locator('body')).not.toContainText(HIDDEN)
}

test('a project masks a related page the editor may not read, and a save keeps it', async ({
  page,
  secondUserPage
}, testInfo) => {
  const { project_id } = await fixtures(page)
  const url = `/admin/projects/projects/update/${project_id}`
  await secondUserPage.goto(url)
  await syncLV(secondUserPage)
  const rows = secondUserPage.locator('.entries-input .selected-entries .identifier')
  await expectMasked(secondUserPage, rows, 2)
  await rows.nth(0).screenshot({ path: testInfo.outputPath('masked-row.png') })

  await secondUserPage.getByTestId('submit').click()
  await expect(secondUserPage).toHaveURL(/\/admin\/projects\/projects$/)
  await secondUserPage.goto(url)
  await syncLV(secondUserPage)
  await expectMasked(secondUserPage, rows, 2)
})

test('a subform row masks a page the editor may not read, takes a pick, and a save keeps both', async ({
  page,
  secondUserPage
}) => {
  const { client_id } = await fixtures(page)
  const url = `/admin/projects/clients/related_rows/${client_id}`
  await secondUserPage.goto(url)
  await syncLV(secondUserPage)
  const field = secondUserPage.locator('.subform-entry .entries-input')
  const rows = field.locator('.selected-entries .identifier')
  await expectMasked(secondUserPage, rows, 2)

  // A pick in the row goes to the row
  await field.getByRole('button', { name: 'Select entries', exact: true }).click()
  const dialog = secondUserPage.getByRole('dialog', { name: 'Select entries', exact: true })
  const option = dialog.locator('.identifier').filter({ hasText: 'Havglimt retreat' })
  await option.click()
  await syncLV(secondUserPage)
  await expect(option).toHaveAttribute('aria-pressed', 'true')
  await expect(rows).toHaveCount(3)
  await expect(rows.nth(2)).toContainText('Havglimt retreat')
  await dialog.getByRole('button', { name: 'Close dialog', exact: true }).click()
  await expect(dialog).not.toBeVisible()

  await secondUserPage.getByTestId('submit').click()
  await expect(secondUserPage).toHaveURL(/\/admin\/projects\/clients$/)
  await secondUserPage.goto(url)
  await syncLV(secondUserPage)
  await expectMasked(secondUserPage, rows, 3)
  await expect(rows.nth(2)).toContainText('Havglimt retreat')
})
