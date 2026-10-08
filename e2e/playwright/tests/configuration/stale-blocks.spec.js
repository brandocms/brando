import { test, expect } from '../../test-support/setupAuth'
import { syncLV } from '../../utils'

// Blocks on older versions (Brando.Content.StaleBlocks). The seeded
// Kulturslider module is on version 3; two blocks on version 1 still hold the
// `link` variable it no longer defines, so the system check warns. From its
// link: drop `link` in every block at once, after the review and the
// confirmation, and the check is clean. Driven in Norwegian, so the locators
// name the translated labels.
test('the system check leads to the blocks on older versions, and dropping a leftover in bulk brings them up to date', async ({
  page,
}) => {
  expect((await page.request.post('/e2e/setup_fixtures/norwegian-admin-user')).ok()).toBe(true)

  await page.goto('/admin/config/utils')
  await syncLV(page)
  const card = page.locator('#system-check')
  await expect(card).toHaveAttribute('aria-busy', 'false', { timeout: 30000 })
  const check = card.locator('li[data-check="modules"]')
  await expect(check).toHaveAttribute('data-status', 'warning')
  await check.getByRole('link', { name: 'Løs blokker' }).click()
  await expect(page).toHaveURL(/\/admin\/config\/content\/modules\/stale-blocks$/)
  await syncLV(page)

  await page.locator('article[data-module="kulturslider"]').getByRole('link', { name: 'Løs blokker' }).click()
  await expect(page).toHaveURL(/\/admin\/config\/content\/modules\/update\/\d+\/stale-blocks$/)
  await syncLV(page)

  // The module's own screen says so too, and leads back here
  await page.locator('a.utils-eyebrow').click()
  await syncLV(page)
  await page.locator('.stale-blocks-notice').getByRole('link', { name: 'Løs blokker' }).click()
  await expect(page).toHaveURL(/\/stale-blocks$/)
  await syncLV(page)

  // Each block with its entry and the value it would lose
  const blocks = page.locator('.stale-block')
  await expect(blocks).toHaveCount(2)
  await expect(blocks.first().getByRole('link', { name: 'Kulturkalender' })).toBeVisible()
  await expect(blocks.first().locator('.stale-block-value')).toContainText('https://by.no/kultur/konserter')

  // Drop `link` in every block
  await page.getByRole('combobox', { name: 'Hva som skjer med link', exact: true }).selectOption({ label: 'Forkast' })
  await syncLV(page)
  await page.getByRole('button', { name: 'Gjennomgå endringer' }).click()
  await syncLV(page)

  const review = page.locator('#stale-blocks-review')
  await expect(review.locator('.stale-blocks-lost li')).toHaveCount(2)
  await review.getByRole('button', { name: 'Løs 2 blokker' }).click()

  // The confirmation is a question, with Cancel first
  const dialog = page.getByRole('dialog', { name: 'Løse 2 blokker?' })
  await expect(dialog.getByRole('button', { name: 'Avbryt' })).toBeFocused()
  await dialog.getByRole('button', { name: 'Løs 2 blokker' }).click()

  await expect(page.locator('.stale-blocks-done')).toBeVisible()
  await expect(page.locator('.stale-block')).toHaveCount(0)

  // The system check is clean
  await page.goto('/admin/config/utils')
  await syncLV(page)
  await expect(card).toHaveAttribute('aria-busy', 'false', { timeout: 30000 })
  await expect(check).toHaveAttribute('data-status', 'ok')
})
