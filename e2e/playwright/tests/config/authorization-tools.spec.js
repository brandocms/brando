import { test, expect } from '../../test-support/setupAuth'
import { syncLV } from '../../utils'
import { readFile } from 'node:fs/promises'

const groupsMode = process.env.BRANDO_AUTHORIZATION_MODE === 'groups'

test('prepares groups and moves a reviewed configuration through export and import', async ({ page }, testInfo) => {
  const errors = []
  page.on('pageerror', error => errors.push(error.message))
  await page.setViewportSize({ width: 1440, height: 1080 })
  await page.goto('/admin/config/utils')
  await syncLV(page)
  await expect(page.locator('.utils-mode')).toHaveText(groupsMode ? 'Groups active' : 'Legacy roles active')
  await expect(page.getByRole('button', { name: 'Prepare groups', exact: true })).toBeDisabled()
  await page.screenshot({ path: testInfo.outputPath('authorization-tools-desktop.png'), fullPage: true })

  await page.getByRole('button', { name: 'Run migration report' }).click()
  await expect(page.locator('#authorization-migration-report')).toBeVisible()
  await expect(page.locator('.utils-rules')).toContainText('E2eProject.Authorization')
  await page.getByRole('button', { name: 'Prepare groups', exact: true }).click()
  await expect(page.getByRole('status')).toContainText('Groups prepared')
  await expect(page.locator('.utils-mode')).toHaveText(groupsMode ? 'Groups active' : 'Legacy roles active')
  await page.screenshot({ path: testInfo.outputPath('authorization-migration-report.png'), fullPage: true })

  await page.getByRole('button', { name: 'Prepare export' }).click()
  const downloadEvent = page.waitForEvent('download')
  await page.getByRole('link', { name: 'Download configuration.json' }).click()
  const download = await downloadEvent
  const config = JSON.parse(await readFile(await download.path(), 'utf8'))
  expect(config.format).toBe('brando.authorization')
  expect(config.groups.some(group => group.preset === 'superuser')).toBe(false)
  const editor = config.groups.find(group => group.key === 'editor')
  editor.name = 'Reviewed editorial team'
  editor.description = 'Prepared in staging, ready for the next release.'
  editor.permissions = ['brando.admin.access', 'brando.pages.read']
  config.groups.push({ key: 'campaign-reviewers', name: 'Campaign reviewers', description: 'An extra pair of eyes.', preset: null, permissions: ['brando.admin.access', 'brando.pages.read'] })
  await page.getByLabel('Group configuration JSON file').setInputFiles({ name: 'reviewed-groups.json', mimeType: 'application/json', buffer: Buffer.from(JSON.stringify(config)) })
  await page.getByRole('button', { name: 'Preview import' }).click()
  const preview = page.locator('#authorization-import-preview')
  await expect(page.locator('#import-preview-title')).toBeFocused()
  await expect(preview).toContainText('Reviewed editorial team')
  await expect(preview).toContainText('Campaign reviewers')
  await preview.locator('summary').filter({ hasText: 'Reviewed editorial team' }).click()
  await expect(preview).toContainText('Permissions removed')
  await page.locator('.utils-transfer').screenshot({ path: testInfo.outputPath('authorization-import-preview.png') })
  await page.getByRole('button', { name: 'Apply configuration' }).click()
  await expect(page.getByRole('status')).toContainText('Configuration imported. 1 groups created, 1 updated')
  await page.getByRole('link', { name: 'Review groups', exact: true }).click()
  await syncLV(page)
  await expect(page.locator('.authorization-group-list')).toContainText('Reviewed editorial team')
  await expect(page.locator('.authorization-group-list')).toContainText('Campaign reviewers')
  if (!groupsMode) await expect(page.locator('.authorization-legacy-notice')).toBeVisible()
  expect(errors).toEqual([])
})

test('shows useful invalid-file feedback and fits narrow screens', async ({ page }, testInfo) => {
  await page.goto('/admin/config/utils')
  await syncLV(page)
  await page.getByLabel('Group configuration JSON file').setInputFiles({ name: 'broken.json', mimeType: 'application/json', buffer: Buffer.from('not valid json') })
  await page.getByRole('button', { name: 'Preview import' }).click()
  await expect(page.getByRole('alert')).toContainText('not valid JSON')
  await expect(page.locator('#authorization-import-preview')).toHaveCount(0)
  await page.getByRole('button', { name: 'Run migration report' }).click()
  await expect(page.locator('#authorization-migration-report')).toBeVisible()
  for (const width of [768, 390]) {
    await page.setViewportSize({ width, height: 900 })
    await expect(page.getByRole('link', { name: 'Review groups', exact: true })).toBeVisible()
    expect(await page.evaluate(() => document.documentElement.scrollWidth <= window.innerWidth)).toBe(true)
    await page.screenshot({ path: testInfo.outputPath(`authorization-tools-${width}.png`), fullPage: true })
  }
})
