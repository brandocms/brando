import { test, expect } from '../test-support/setupAuth'

const formValues = page => page.locator('#tracking-form').evaluate(form => Object.fromEntries(new FormData(form)))
const editor = page => page.locator('#tracking_code-code .cm-content')

test.beforeEach(async ({ page }) => {
  await page.goto('/admin/__change_tracking')
  await expect(editor(page)).toHaveText('original source')
  await expect(page.locator('#tracking_date')).toHaveValue('2026-09-01')
})

test('parent replacement and clearing reach ignored widgets without echoing edits', async ({ page }) => {
  await page.locator('#replace-values').click()
  await expect(editor(page)).toHaveText('restored source')
  await expect(page.locator('#tracking_date')).toHaveValue('2026-09-08')
  await expect(page.locator('#tracking_datetime')).toHaveValue('2026-09-08T15:30:00.000Z')
  await expect(page.locator('#tracking_date-datepicker input:not([type="hidden"])')).toHaveValue('08/09/26')
  await expect(page.locator('#change-count')).toHaveText('0')
  await expect(page.locator('[name="tracking[date]"]')).toHaveCount(1)
  await expect(page.locator('[name="tracking[datetime]"]')).toHaveCount(1)
  await page.locator('#submit-values').click()
  await expect(page.locator('#submitted-values')).toContainText('restored source')

  await editor(page).click()
  await editor(page).press('ControlOrMeta+a')
  await page.keyboard.insertText('edited after restore')
  await expect(page.locator('#change-count')).toHaveText('1')
  await page.locator('#unrelated-update').click()
  await expect(page.locator('#tick-count')).toHaveText('1')
  await expect(editor(page)).toHaveText('edited after restore')
  expect((await formValues(page))['tracking[code]']).toBe('edited after restore')

  await page.locator('#clear-values').click()
  await expect(editor(page)).toHaveText('')
  await expect(page.locator('#tracking_date')).toHaveValue('')
  await expect(page.locator('#tracking_datetime')).toHaveValue('')
  await expect(page.locator('#tracking_date-datepicker input:not([type="hidden"])')).toHaveValue('')
  await expect(page.locator('#change-count')).toHaveText('1')
  await page.locator('#submit-values').click()
  await expect(page.locator('#submitted-values')).toHaveText('{"code":"","date":"","datetime":""}')
})

test('unrelated patches preserve local edits and removing controls destroys their widgets', async ({ page }) => {
  // No input event: this represents an edit waiting for its debounce/commit.
  await page.evaluate(() => {
    const date = document.querySelector('#tracking_date')
    date._flatpickr.setDate('2026-09-05', false)
    const hook = window.liveSocket.main.getHook(document.querySelector('#tracking_code-code'))
    window.trackingEditor = hook.view
    hook.view.update([hook.view.state.update({ changes: { from: 0, to: hook.view.state.doc.length, insert: 'pending source' } })])
    hook.$input.value = 'pending source'
  })
  await page.locator('#unrelated-update').click()
  await expect(page.locator('#tick-count')).toHaveText('1')
  await expect(editor(page)).toHaveText('pending source')
  expect((await formValues(page))['tracking[code]']).toBe('pending source')
  await expect(page.locator('#tracking_date')).toHaveValue('2026-09-05')
  await expect(page.locator('#change-count')).toHaveText('0')
  await page.locator('#remove-controls').click()
  await expect(editor(page)).toHaveCount(0)
  await expect(page.locator('.flatpickr-calendar')).toHaveCount(0)
  expect(await page.evaluate(() => window.trackingEditor.destroyed)).toBe(true)
})
