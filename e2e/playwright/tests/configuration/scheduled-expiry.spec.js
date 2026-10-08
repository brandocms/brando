import { test, expect } from '../../test-support/setupAuth'
import { syncLV } from '../../utils'

// Scheduled expiry (#3080): Expires in the entry's scheduling drawer, the
// label in the listing, the dashboard's "Expiring soon" panel and the
// calendar. Driven in Norwegian, so the locators name the translated labels.

async function factory(page, schema, attributes) {
  const response = await page.request.post('/__e2e/db/factory', { data: { schema, attributes, creator_id: 1, fields: ['id'] } })
  expect(response.ok(), await response.text()).toBeTruthy()
  return response.json()
}

// flatpickr's Norwegian day labels: "Oktober 11, 2026"
const MONTHS = ['Januar', 'Februar', 'Mars', 'April', 'Mai', 'Juni', 'Juli', 'August', 'September', 'Oktober', 'November', 'Desember']
const dayLabel = date => `${MONTHS[date.getMonth()]} ${date.getDate()}, ${date.getFullYear()}`

test('an expiry set in the entry shows in the listing, on the dashboard and in the calendar', async ({ page }, testInfo) => {
  const client = await factory(page, 'E2eProject.Projects.Client', {
    name: 'Expiry owner', slug: 'expiry-owner', status: 'published', language: 'en',
  })
  const project = await factory(page, 'E2eProject.Projects.Project', {
    title: 'Winter campaign', slug: 'winter-campaign', client_id: client.id, introduction: '<p>Intro</p>',
    status: 'published', language: 'en',
  })

  expect((await page.request.post('/e2e/setup_fixtures/norwegian-admin-user')).ok()).toBe(true)
  await page.setViewportSize({ width: 1440, height: 900 })

  await page.goto(`/admin/projects/projects/update/${project.id}`)
  await syncLV(page)
  await page.getByRole('button', { name: 'Planlagt publisering', exact: true }).click()
  const drawer = page.locator('[id$="-scheduled-publishing-drawer"]')
  await expect(drawer).toBeVisible()
  await expect(drawer.getByText('Utløper', { exact: true })).toBeVisible()

  // Three days ahead, in this month or among the next month's first days
  const expires = new Date(Date.now() + 3 * 24 * 60 * 60 * 1000)
  const picker = drawer.locator('[id$="_unpublish_at-datetimepicker"]')
  await picker.locator('input').filter({ visible: true }).click()
  const calendar = page.locator('.flatpickr-calendar.open')
  await calendar.locator(`.flatpickr-day[aria-label="${dayLabel(expires)}"]`).click()
  await page.keyboard.press('Escape')
  await expect.poll(async () => Date.parse(await picker.locator('input[name$="[unpublish_at]"]').inputValue())).toBeGreaterThan(Date.now())
  await syncLV(page)
  await page.screenshot({ path: testInfo.outputPath('expires-drawer.png') })

  await drawer.locator('.drawer-close-button').click()
  await page.getByTestId('submit').click()
  await expect(page).toHaveURL(/\/admin\/projects\/projects$/)
  await syncLV(page)

  // The listing: under the status
  const row = page.locator(`#list-row-${project.id}`)
  const label = row.getByTestId('listing-expiry')
  await expect(label).toBeVisible()
  const expiresAt = await label.getAttribute('datetime')
  expect(Date.parse(expiresAt)).toBeGreaterThan(Date.now())
  await page.screenshot({ path: testInfo.outputPath('expires-listing.png') })

  // The dashboard: in the side column's "Expiring soon"
  await page.goto('/admin')
  await syncLV(page)
  const panel = page.getByTestId('dashboard-expiring')
  await expect(panel.getByRole('heading', { name: 'Utløper snart', exact: true })).toBeVisible()
  await expect(panel.getByRole('link', { name: 'Winter campaign', exact: true })).toHaveAttribute(
    'href',
    `/admin/projects/projects/update/${project.id}`
  )
  await page.screenshot({ path: testInfo.outputPath('expires-dashboard.png'), fullPage: true })

  // The calendar: on its day, as an expiry
  const day = new Intl.DateTimeFormat('en-CA', { timeZone: 'Europe/Oslo' }).format(new Date(Date.parse(expiresAt)))
  await page.goto(`/admin/calendar?date=${day}`)
  await syncLV(page)
  const item = page.locator(`#calendar-day-${day} #calendar-item-expire-projects_project-${project.id}`)
  await expect(item).toHaveAttribute('data-kind', 'expire')
  await expect(item.getByRole('link', { name: 'Winter campaign', exact: true })).toBeVisible()
})
