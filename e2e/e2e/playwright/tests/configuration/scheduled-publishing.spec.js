import { test, expect } from '../../test-support/setupAuth'
import { syncLV } from '../../utils'

test('selects a future publishing date and manages the publishing queue', async ({ page }) => {
  await page.goto('/admin/pages')
  await syncLV(page)
  await page.getByRole('link', { name: 'Create page' }).click()
  await syncLV(page)

  const title = 'Scheduled publishing test'
  await page.getByLabel('Title', { exact: true }).fill(title)
  await page.getByLabel('URI').fill('scheduled-publishing-test')

  await page.getByRole('button', { name: 'Scheduled publishing' }).click()

  const drawer = page.locator('[id$="-scheduled-publishing-drawer"]')
  await expect(drawer).toBeVisible()

  const publishAtInput = drawer.locator('input[name="page[publish_at]"]')
  const datePickerInput = drawer.locator('input').filter({ visible: true })
  const publishAtDate = new Date(Date.now() + 24 * 60 * 60 * 1000)
  const publishAtDay = publishAtDate.toLocaleDateString('en-US', {
    month: 'long',
    day: 'numeric',
    year: 'numeric',
  })

  await datePickerInput.click()
  await page
    .locator(`.flatpickr-calendar.open .flatpickr-day[aria-label="${publishAtDay}"]`)
    .click()
  await page.keyboard.press('Escape')

  const publishAt = await publishAtInput.inputValue()
  expect(Date.parse(publishAt)).toBeGreaterThan(Date.now())

  const fixtureResponse = await page.request.post('/__e2e/db/factory', {
    data: {
      schema: 'Brando.Pages.Page',
      attributes: {
        title,
        uri: 'scheduled-publishing-test',
        publish_at: publishAt,
        status: 'published',
      },
      creator_id: 1,
      fields: ['title', 'publish_at'],
      oban_testing: 'manual',
    },
  })
  expect(fixtureResponse.ok()).toBeTruthy()

  await page.goto('/admin/config/scheduled_publishing')
  await syncLV(page)
  await expect(page.getByRole('heading', { name: 'Scheduled Publishing' })).toBeVisible()

  const scheduledJob = page.locator('.scheduled-publishing-live tr').filter({ hasText: title })
  await expect(scheduledJob).toBeVisible()

  await page.getByRole('button', { name: 'Refresh job queue' }).click()
  await syncLV(page)
  await expect(scheduledJob).toBeVisible()

  await scheduledJob.getByRole('button', { name: 'Delete job' }).click()
  await syncLV(page)
  await expect(scheduledJob).toHaveCount(0)
})
