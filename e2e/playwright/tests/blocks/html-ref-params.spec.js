import { test, expect } from '../../test-support/setupAuth'
import { syncLV, toggleLivePreview, getPreviewFrame, waitForPreviewReady } from '../../utils'

// An HTML ref is a template a superuser writes, with typed parameters that
// editors fill in (`Brando.Villain.Blocks.HtmlBlock`). The "html-ref"
// fixture's module renders `<div class="checkin" data-checkin="{{ checkin_id }}">`
// with `checkin_id` an ID parameter.
const addCheckinBlock = async (page) => {
  await page.goto('/admin/pages/create')
  await syncLV(page)
  await page.getByLabel('Title', { exact: true }).fill('Check-in page')
  await page.getByLabel('URI').fill('check-in')
  await page.getByRole('button', { name: 'Add block', exact: true }).click()
  await page.getByRole('button', { name: '05 LIVE PREVIEW TEST' }).click()
  await expect(page.locator('.module-picker-namespace.active')).toContainText('05 LIVE PREVIEW TEST')
  await page.getByRole('button', { name: 'Check-in widget', exact: true }).click()
  await syncLV(page)
  return page.locator('.html-block')
}

test.describe('HTML ref parameters', () => {
  test.setTimeout(60000)

  test('an editor fills in a parameter and the preview renders it', async ({ page }) => {
    expect((await page.request.post('/e2e/setup_fixtures/html-ref-editor')).ok()).toBe(true)
    const block = await addCheckinBlock(page)
    const input = block.getByLabel('Check-in ID')

    // The value form only: no markup editor, no parameter declarations
    await expect(input).toBeVisible()
    await expect(block.locator('.code-editor')).toHaveCount(0)
    await expect(block.getByRole('button', { name: 'Add parameter' })).toHaveCount(0)

    await toggleLivePreview(page)
    await waitForPreviewReady(page)
    const frame = getPreviewFrame(page)

    await input.fill('abc-123')
    await syncLV(page)
    await expect(frame.locator('.checkin')).toHaveAttribute('data-checkin', 'abc-123')

    // A value that is not an ID renders as nothing, and the field says so
    await input.fill('abc 123')
    await syncLV(page)
    await expect(frame.locator('.checkin')).toHaveAttribute('data-checkin', '')
    await expect(block.locator('.field-error')).toHaveCount(1)
  })

  test('a superuser edits the HTML and declares parameters', async ({ page }) => {
    expect((await page.request.post('/e2e/setup_fixtures/html-ref')).ok()).toBe(true)
    const block = await addCheckinBlock(page)

    await expect(block.locator('.code-editor')).toBeVisible()
    await expect(block.getByLabel('Key')).toHaveValue('checkin_id')
    await expect(block.getByLabel('Check-in ID')).toBeVisible()

    await block.getByRole('button', { name: 'Add parameter' }).click()
    await syncLV(page)
    await expect(block.getByLabel('Key')).toHaveCount(2)
  })
})
