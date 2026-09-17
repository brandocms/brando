import { test, expect } from '../../test-support/setupAuth'
import { syncLV } from '../../utils'
import { readFile, writeFile } from 'node:fs/promises'

async function screenshot(page, testInfo, name) {
  await page.evaluate(() => window.scrollTo(0, 0))
  await page.screenshot({ path: testInfo.outputPath(name + '.png'), fullPage: true })
  const measurements = await page.evaluate(() => {
    const selectors = [
      '.transfer-related > p', '.transfer-related-row', '.transfer-type-filters', '.transfer-entry-metadata',
      '.markdown-source-field p', '#markdown-folder-selection .markdown-source-note',
      '.markdown-folder-files', '#markdown-folder-selection .markdown-source-actions',
      '.markdown-source-path', '.markdown-source-meta', '.markdown-source-row .markdown-source-actions',
      '.workspace-heading', '.content-list .list-row', '.global-set-title', '.global-set-title small',
      '.global-set-name', '.global-set-key'
    ]
    return Object.fromEntries(selectors.map(selector => [selector, [...document.querySelectorAll(selector)].map(el => {
      const css = getComputedStyle(el)
      const box = el.getBoundingClientRect()
      return { text: el.textContent.trim().slice(0, 90), x: box.x, y: box.y, width: box.width, height: box.height,
        font: css.fontSize, lineHeight: css.lineHeight, marginTop: css.marginTop, marginBottom: css.marginBottom,
        paddingTop: css.paddingTop, paddingBottom: css.paddingBottom, borderTop: css.borderTopWidth, borderBottom: css.borderBottomWidth }
    })]))
  })
  await writeFile(testInfo.outputPath(name + '.json'), JSON.stringify(measurements, null, 2))
  const detail = {
    'export-relations-norwegian': '.transfer-related',
    'export-types-norwegian': '.transfer-main',
    'markdown-folder-desktop': '.markdown-source-setup',
    'markdown-desktop': '.markdown-documents',
    'globals-list-desktop': '.global-set-title',
    'galleries-desktop': '.galleries-workspace'
  }[name]
  if (detail && await page.locator(detail).count()) {
    await page.locator(detail).screenshot({ path: testInfo.outputPath(name + '-detail.png') })
  }
}
async function narrow(page) {
  await page.setViewportSize({ width: 390, height: 844 })
  await page.waitForTimeout(650)
  await expect.poll(() => page.evaluate(() => document.documentElement.scrollWidth)).toBeLessThanOrEqual(390)
}
async function norwegian(page) {
  expect((await page.request.post('/e2e/setup_fixtures/norwegian-admin-user')).ok()).toBeTruthy()
}

test('type filters preserve selection and related entries can reuse unchanged destinations', async ({ page }, testInfo) => {
  await page.setViewportSize({ width: 1440, height: 1000 })
  await page.request.post('/e2e/setup_fixtures/content-transfer-related')
  await page.goto('/admin/config/import-export')
  await syncLV(page)
  const campaign = page.locator('.transfer-entry').filter({ has: page.getByRole('heading', { name: 'Campaign launch', exact: true }) })
  await expect(campaign.locator('.transfer-entry-metadata')).toContainText('Brando Admin')
  await expect(campaign.locator('time')).toHaveAttribute('datetime', /^\d{4}-\d{2}-\d{2}T/)
  const filters = page.getByRole('group', { name: 'Content types', exact: true })
  await filters.getByRole('button', { name: 'Page', exact: true }).click()
  await expect.poll(() => page.locator('.transfer-entry .transfer-meta > span:first-child').allTextContents()).toEqual(['Page', 'Page', 'Page'])
  await page.getByRole('button', { name: 'Select Campaign launch', exact: true }).click()
  await filters.getByRole('button', { name: 'Fragment', exact: true }).click()
  await expect(filters.locator('[aria-pressed="true"]')).toHaveCount(2)
  await filters.getByRole('button', { name: 'Page', exact: true }).click()
  await expect(page.getByRole('button', { name: 'Select Campaign launch', exact: true })).toHaveCount(0)
  await expect(page.locator('.transfer-summary')).toContainText('Campaign launch')
  await filters.getByRole('button', { name: 'All types' }).click()
  await expect(page.getByRole('button', { name: 'Select Campaign launch', exact: true })).toHaveAttribute('aria-pressed', 'true')
  await filters.getByRole('button', { name: 'Page', exact: true }).click()
  await filters.getByRole('button', { name: 'Fragment', exact: true }).click()
  await screenshot(page, testInfo, 'export-types-desktop')
  await narrow(page)
  await screenshot(page, testInfo, 'export-types-mobile')
  await page.setViewportSize({ width: 1440, height: 1000 })
  await page.getByRole('button', { name: 'Prepare export', exact: true }).click()
  await expect(page.locator('.transfer-reference-paths')).toContainText('Campaign launch')
  await page.getByText('Included dependencies', { exact: true }).click()
  await expect(page.locator('.transfer-dependency-groups')).not.toContainText('Destination page')
  await screenshot(page, testInfo, 'export-relations-desktop')
  await page.getByRole('button', { name: 'Include entry', exact: true }).click()
  await expect(page.locator('.transfer-review-list article')).toHaveCount(2)
  const download = page.waitForEvent('download')
  await page.locator('#transfer-download').click()
  const binary = await readFile(await (await download).path())
  await page.getByRole('button', { name: 'Import content', exact: true }).click()
  await page.locator('#transfer-upload-form input[type=file]').setInputFiles({ name: 'relations.zip', mimeType: 'application/zip', buffer: binary })
  await page.getByRole('button', { name: 'Review bundle', exact: true }).click()
  const incoming = page.locator('.transfer-whole-entry').filter({ has: page.getByRole('heading', { name: 'Campaign launch', exact: true }) })
  const parent = page.locator('.transfer-whole-entry').filter({ has: page.getByRole('heading', { name: 'Destination page', exact: true }) })
  await incoming.getByLabel('URI', { exact: true }).fill('campaign-with-reused-parent')
  await parent.getByLabel('Import action', { exact: true }).selectOption('reuse')
  await parent.getByLabel('Destination entry', { exact: true }).selectOption({ label: 'Destination page · English' })
  await expect(parent.getByLabel('Publication', { exact: true })).toHaveCount(0)
  await expect(parent.getByText('Review fields & content', { exact: true })).toHaveCount(0)
  await expect(page.getByRole('button', { name: 'Apply content import' })).toBeEnabled()
  await screenshot(page, testInfo, 'import-reuse-desktop')
  await page.getByRole('button', { name: 'Apply content import' }).click()
  await expect(page.locator('#transfer-result')).toContainText('1 entry saved')

  await norwegian(page)
  await page.goto('/admin/config/import-export')
  await syncLV(page)
  const types = page.getByRole('group', { name: 'Innholdstyper', exact: true })
  await types.getByRole('button', { name: 'Side', exact: true }).click()
  await types.getByRole('button', { name: 'Fragment', exact: true }).click()
  await page.getByRole('button', { name: 'Velg Campaign launch', exact: true }).first().click()
  await screenshot(page, testInfo, 'export-types-norwegian')
  await narrow(page)
  await screenshot(page, testInfo, 'export-types-norwegian-mobile')
  await page.setViewportSize({ width: 1440, height: 1000 })
  await page.getByRole('button', { name: 'Klargjør eksport', exact: true }).click()
  await expect(page.locator('.transfer-reference-paths')).toContainText('Brukes av')
  await page.getByText('Inkluderte avhengigheter', { exact: true }).click()
  await screenshot(page, testInfo, 'export-relations-norwegian')
  await narrow(page)
  await screenshot(page, testInfo, 'export-relations-norwegian-mobile')
})
