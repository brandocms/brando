import { test, expect } from '../test-support/setupAuth'
import { syncLV } from '../utils'

// The calendar (#3081): what is planned for entries by day, in the site's
// time zone (Europe/Oslo here). Driven in Norwegian, so the locators name the
// translated labels; dates and times are data, not copy.

async function factory(page, schema, attributes, extra = {}) {
  const response = await page.request.post('/__e2e/db/factory', {
    data: { schema, attributes, creator_id: 1, fields: ['id'], ...extra },
  })
  expect(response.ok(), await response.text()).toBeTruthy()
  return response.json()
}

const DAY = 24 * 60 * 60 * 1000
// "2026-10-11", the date in Oslo
const osloDate = date => new Intl.DateTimeFormat('en-CA', { timeZone: 'Europe/Oslo' }).format(date)
// Oslo's offset from UTC at an instant, in milliseconds (summer or winter time)
const osloOffset = instant =>
  new Date(instant.toLocaleString('en-US', { timeZone: 'Europe/Oslo' })) - new Date(instant.toLocaleString('en-US', { timeZone: 'UTC' }))
const addDays = (iso, days) => new Date(Date.parse(`${iso}T12:00:00Z`) + days * DAY).toISOString().slice(0, 10)

// A pending project, published three days from now at 09:30 Oslo time, with
// its job kept (the E2E Oban runs jobs at once otherwise)
async function scheduledProject(page, title, slug) {
  const client = await factory(page, 'E2eProject.Projects.Client', {
    name: `${title} owner`, slug: `${slug}-owner`, status: 'published', language: 'en',
  })
  const day = osloDate(new Date(Date.now() + 3 * DAY))
  const utc = new Date(Date.parse(`${day}T09:30:00Z`) - osloOffset(new Date(`${day}T12:00:00Z`)))
  const project = await factory(
    page,
    'E2eProject.Projects.Project',
    { title, slug, client_id: client.id, introduction: '<p>Intro</p>', status: 'pending', language: 'en', publish_at: utc.toISOString() },
    { oban_testing: 'manual' }
  )
  return { project, day }
}

const itemFor = (page, project) => page.locator(`[id^="calendar-item-publish-projects_project-${project.id}"]`)
const dayCell = (page, iso) => page.locator(`#calendar-day-${iso}`)

test.beforeEach(async ({ page }) => {
  expect((await page.request.post('/e2e/setup_fixtures/norwegian-admin-user')).ok()).toBe(true)
})

test('dragging an item to another day asks first, then moves it, keeping the time', async ({ page }, testInfo) => {
  const { project, day } = await scheduledProject(page, 'Harbour bath opening', 'harbour-bath-opening')
  // Another day of the same week that has not passed
  const sunday = new Date(Date.parse(`${day}T12:00:00Z`)).getUTCDay() === 0
  const target = addDays(day, sunday ? -1 : 1)

  await page.setViewportSize({ width: 1440, height: 1000 })
  await page.goto('/admin')
  await syncLV(page)
  await page.locator('#nav-sections').getByRole('link', { name: 'Kalender', exact: true }).click()
  await expect(page).toHaveURL(/\/admin\/calendar$/)
  await page.goto(`/admin/calendar?view=week&date=${day}`)
  await syncLV(page)
  await expect(page.locator('#calendar-view-week')).toHaveAttribute('aria-current', 'page')

  const item = itemFor(page, project)
  await expect(dayCell(page, day).locator(item)).toBeVisible()
  await expect(item.locator('.calendar-item-time')).toHaveText('09:30')
  await expect(item).toHaveAttribute('draggable', 'true')

  await item.dragTo(dayCell(page, target))
  const dialog = page.locator('dialog.admin-dialog')
  await expect(dialog).toBeVisible()
  await page.screenshot({ path: testInfo.outputPath('calendar-drag-confirm.png') })

  // Cancelling leaves it where it was
  await dialog.getByRole('button', { name: 'Avbryt', exact: true }).click()
  await expect(dialog).toBeHidden()
  await expect(dayCell(page, day).locator(item)).toBeVisible()

  await item.dragTo(dayCell(page, target))
  await page.locator('dialog.admin-dialog').getByRole('button', { name: 'Flytt', exact: true }).click()
  await syncLV(page)

  await expect(dayCell(page, target).locator(item)).toBeVisible()
  await expect(dayCell(page, day).locator(item)).toHaveCount(0)
  await expect(item.locator('.calendar-item-time')).toHaveText('09:30')
  await page.screenshot({ path: testInfo.outputPath('calendar-week-moved.png') })

  // The entry form has the new date
  await item.getByRole('link').click()
  await expect(page).toHaveURL(`/admin/projects/projects/update/${project.id}`)
  await syncLV(page)
  const publishAt = await page.locator('input[name$="[publish_at]"]').inputValue()
  expect(osloDate(new Date(publishAt))).toBe(target)
})

test('the keyboard moves between days, and Move to… moves an item without dragging', async ({ page }, testInfo) => {
  const { project, day } = await scheduledProject(page, 'Winter menu', 'winter-menu')
  const target = addDays(day, 2)

  await page.setViewportSize({ width: 1440, height: 1000 })
  await page.goto(`/admin/calendar?date=${day}`)
  await syncLV(page)

  // One tab stop for the days; arrows move a day and a week
  const cell = dayCell(page, day)
  await expect(cell).toHaveAttribute('tabindex', '0')
  await cell.focus()
  await page.keyboard.press('ArrowRight')
  await expect(dayCell(page, addDays(day, 1))).toBeFocused()
  await page.keyboard.press('ArrowLeft')
  await page.keyboard.press('ArrowDown')
  await expect(dayCell(page, addDays(day, 7))).toBeFocused()
  await page.keyboard.press('ArrowUp')
  await expect(cell).toBeFocused()

  // Enter goes into the day's first item; Escape back to the day
  await page.keyboard.press('Enter')
  await expect(itemFor(page, project).getByRole('link')).toBeFocused()
  await page.keyboard.press('Escape')
  await expect(cell).toBeFocused()

  // Move to…: the dialog's date field, then the move
  await page.keyboard.press('Enter')
  await page.keyboard.press('Tab')
  const move = itemFor(page, project).getByRole('button', { name: 'Flytt «Winter menu» til en annen dag', exact: true })
  await expect(move).toBeFocused()
  await page.keyboard.press('Enter')
  const dialog = page.locator('#calendar-move')
  await expect(dialog).toBeVisible()
  await expect(dialog.locator('#calendar-move-date')).toHaveValue(day)
  await dialog.locator('#calendar-move-date').fill(target)
  await expect(dialog.locator('#calendar-move-summary')).toContainText('09:30')
  await page.screenshot({ path: testInfo.outputPath('calendar-move-dialog.png') })
  await dialog.getByRole('button', { name: 'Flytt', exact: true }).click()
  await syncLV(page)

  await expect(dialog).toHaveCount(0)
  await expect(dayCell(page, target).locator(itemFor(page, project))).toBeVisible()
})

test('the type filter, and a list of days on a phone', async ({ page }, testInfo) => {
  const { project, day } = await scheduledProject(page, 'Opening night', 'opening-night')

  await page.setViewportSize({ width: 1440, height: 1000 })
  await page.goto(`/admin/calendar?date=${day}`)
  await syncLV(page)
  await expect(itemFor(page, project)).toBeVisible()

  const type = page.getByRole('combobox', { name: 'Innholdstype' })
  await type.selectOption('pages.page')
  await expect(page).toHaveURL(/type=pages\.page/)
  await expect(itemFor(page, project)).toHaveCount(0)
  await type.selectOption('projects.project')
  await expect(itemFor(page, project)).toBeVisible()

  await page.setViewportSize({ width: 390, height: 844 })
  await expect(page.locator('.calendar-weekdays')).toBeHidden()
  await expect(dayCell(page, day)).toBeVisible()
  await expect(itemFor(page, project).getByRole('button', { name: 'Flytt «Opening night» til en annen dag', exact: true })).toBeVisible()
  // Days with nothing planned are left out, today excepted
  const empty = addDays(day, 1)
  await expect(dayCell(page, empty)).toBeHidden()
  const overflow = await page.evaluate(() => document.documentElement.scrollWidth - window.innerWidth)
  expect(overflow).toBeLessThanOrEqual(0)
  await page.screenshot({ path: testInfo.outputPath('calendar-phone.png'), fullPage: true })
})
