import { test, expect } from '../../test-support/setupAuth'
import { syncLV } from '../../utils'

// #2984: the status filters count their entries under the listing's other
// filters, and the footer counts, shows the range and picks the page size.

async function pages(page, prefix, statuses) {
  for (const [i, status] of statuses.entries()) {
    const response = await page.request.post('/__e2e/db/factory', {
      data: {
        schema: 'Brando.Pages.Page',
        attributes: { title: `${prefix} ${i + 1}`, uri: `${prefix.toLowerCase()}-${i + 1}`, language: 'en', status },
        creator_id: 1,
        fields: ['id']
      }
    })
    expect(response.ok(), await response.text()).toBeTruthy()
  }
}

const count = (page, status) => page.locator(`.statuses button[phx-value-status="${status}"] .status-count`)

test('status filters count the filtered entries and follow a status change', async ({ page }) => {
  await pages(page, 'Counted', ['draft', 'draft', 'pending'])
  await page.goto('/admin/pages?filter:title=Counted')
  await syncLV(page)

  await expect(count(page, 'draft')).toHaveText('2')
  await expect(count(page, 'pending')).toHaveText('1')
  await expect(count(page, 'published')).toHaveText('0')
  await expect(count(page, 'deleted')).toHaveText('0')
  // A status without entries stays, muted
  await expect(page.locator('.statuses button[phx-value-status="published"]')).toHaveClass(/is-empty/)
  await expect(page.locator('.statuses button[phx-value-status="draft"]')).not.toHaveClass(/is-empty/)

  // The counts ignore the status filter itself
  await page.locator('.statuses button[phx-value-status="draft"]').click()
  await expect(page).toHaveURL(/status=draft/)
  await expect(page.locator('.content-list .list-row')).toHaveCount(2)
  await expect(count(page, 'pending')).toHaveText('1')

  // Publishing one from the listing moves it to the other count
  const row = page.locator('.content-list .list-row').first()
  await row.locator('.status').first().click()
  await row.locator('.status-dropdown button:has(circle.published)').click()
  await expect(count(page, 'draft')).toHaveText('1')
  await expect(count(page, 'published')).toHaveText('1')
  await expect(page.locator('.statuses button[phx-value-status="published"]')).not.toHaveClass(/is-empty/)
})

test('the footer shows the range and changes the page size', async ({ page }) => {
  await pages(page, 'Paged', Array(30).fill('published'))
  await page.goto('/admin/pages?filter:title=Paged')
  await syncLV(page)

  const footer = page.getByTestId('listing-footer')
  await expect(footer.getByTestId('listing-count')).toContainText('30')
  await expect(footer.getByTestId('listing-range')).toContainText('1–25')
  await expect(footer.getByTestId('listing-range')).toContainText('30')
  await expect(page.locator('.content-list .list-row')).toHaveCount(25)

  const perPage = footer.getByRole('combobox')
  await expect(perPage).toHaveValue('25')
  await perPage.selectOption('50')
  await expect(page).toHaveURL(/limit=50/)
  await expect(page.locator('.content-list .list-row')).toHaveCount(30)
  await expect(footer.getByTestId('listing-range')).toHaveCount(0)
  await expect(footer.getByRole('combobox')).toHaveValue('50')

  await footer.getByRole('combobox').selectOption('0')
  await expect(page).toHaveURL(/limit=0/)
  await expect(footer.getByRole('combobox')).toHaveValue('0')
  await expect(page.locator('.content-list .list-row')).toHaveCount(30)
})

test('an empty listing reads 0 entries without a range or page size', async ({ page }) => {
  await page.goto('/admin/pages?filter:title=no-such-page')
  await syncLV(page)

  const footer = page.getByTestId('listing-footer')
  await expect(footer.getByTestId('listing-count')).toContainText('0')
  await expect(footer.getByTestId('listing-range')).toHaveCount(0)
  await expect(footer.getByRole('combobox')).toHaveCount(0)
  await expect(page.locator('.statuses .status-count')).toHaveText(['0', '0', '0', '0', '0'])
})
