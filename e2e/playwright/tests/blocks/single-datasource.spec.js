import { test, expect } from '../../test-support/setupAuth'
import { syncLV, setEntryStatus } from '../../utils'

for (const adapter of ['Liquid', 'HEEx']) test(`single datasource chooses, replaces and clears one entry (${adapter})`, async ({ page }, testInfo) => {
  expect((await page.request.post('/e2e/setup_fixtures/single-datasource-modules')).ok()).toBe(true)
  expect((await page.request.post('/e2e/setup_fixtures/norwegian-admin-user')).ok()).toBe(true)
  await page.goto('/admin/pages/create')
  await syncLV(page)
  const title = `Single picker ${adapter}`
  const uri = `single-picker-${adapter.toLowerCase()}`
  await page.getByLabel('Tittel', { exact: true }).fill(title)
  await page.getByLabel('URI', { exact: true }).fill(uri)
  await setEntryStatus(page, 'published')
  await page.getByRole('button', { name: 'Legg til blokk', exact: true }).click()
  await page.getByRole('button', { name: 'DATAKILDE' }).click()
  await page.locator('.module-picker').getByRole('button', { name: `Ett prosjekt (${adapter})`, exact: true }).click()
  await syncLV(page)

  const selected = page.locator('.module-datasource-selected .selected-entries .identifier')
  const picker = page.locator('.modal[id^="select-entries-"]')
  const openPicker = async () => {
    await page.getByRole('button', { name: 'Velg element', exact: true }).click()
    await expect(picker).toBeVisible()
    await syncLV(page)
  }
  const choose = async name => {
    await picker.getByRole('button').filter({ hasText: `Test Project ${name}` }).click()
    await expect(selected).toHaveCount(1)
    await expect(selected).toContainText(`Test Project ${name}`)
  }
  const closePicker = async () => {
    await picker.locator('.modal-close').click()
    await expect(picker).toBeHidden()
  }
  const saveAndReopen = async () => {
    await page.getByTestId('submit').click()
    await expect(page).toHaveURL(/\/admin\/pages$/)
    await syncLV(page)
    await page.getByRole('link', { name: title, exact: true }).click()
    await syncLV(page)
  }
  const rendered = async () => {
    const response = await page.request.get(`/${uri}`)
    expect(response.ok()).toBe(true)
    return response.text()
  }

  await expect(selected).toHaveCount(0)
  await openPicker()
  await choose('Alpha')
  await choose('Beta')
  await expect(picker.locator('.identifier[aria-pressed="true"]')).toHaveCount(1)
  await closePicker()
  await saveAndReopen()
  await expect(selected).toHaveCount(1)
  await expect(selected).toContainText('Test Project Beta')
  expect(await rendered()).toContain('Test Project Beta')
  expect(await rendered()).not.toContain('Test Project Alpha')

  // Replace a persisted choice and reselect it before saving (reuse its join id).
  await openPicker()
  await choose('Alpha')
  await choose('Beta')
  await closePicker()
  const block = page.locator('.entry-block [data-block-uid]').first()
  await block.locator('.block-action-dropdown > .block-action').first().click()
  await block.locator('.block-action-dropdown-content').getByRole('button', { name: 'Konfigurer', exact: true }).click()
  const config = page.locator('.modal.visible')
  await config.getByLabel('Beskrivelse av blokk').fill('Chosen project')
  await config.getByLabel('Beskrivelse av blokk').blur()
  await syncLV(page)
  await config.locator('.modal-footer').getByRole('button', { name: 'Ferdig', exact: true }).click()
  await expect(config).toBeHidden()
  await expect(selected).toContainText('Test Project Beta')

  for (const width of [1440, 390]) {
    await page.setViewportSize({ width, height: 1000 })
    const field = page.locator('.block-datasource')
    await field.scrollIntoViewIfNeeded()
    expect(await field.evaluate(el => el.scrollWidth <= el.clientWidth)).toBe(true)
    await field.screenshot({ path: testInfo.outputPath(`single-datasource-${width}.png`) })
  }
  await page.setViewportSize({ width: 1440, height: 1000 })
  await saveAndReopen()
  await expect(selected).toHaveCount(1)
  await expect(selected).toContainText('Test Project Beta')

  await selected.getByRole('button', { name: 'Fjern', exact: true }).click()
  await expect(selected).toHaveCount(0)
  await saveAndReopen()
  await expect(selected).toHaveCount(0)
  expect(await rendered()).not.toContain('Test Project Beta')

  await openPicker()
  await choose('Gamma')
  await picker.getByRole('button').filter({ hasText: 'Test Project Gamma' }).click()
  await expect(selected).toHaveCount(0)
})
