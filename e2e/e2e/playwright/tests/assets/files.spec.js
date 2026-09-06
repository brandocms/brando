import { randomUUID } from 'node:crypto'
import { readFileSync } from 'node:fs'
import { test, expect } from '../../test-support/setupAuth'
import { syncLV } from '../../utils'

async function uploadFile(page) {
  const filename = `annual-report-${randomUUID().slice(0, 8)}.pdf`
  const original = readFileSync('./fixtures/test.pdf')
  await page.goto('/admin/assets/files')
  await syncLV(page)
  await page.locator('#assets-file-browser-main input[type="file"]').setInputFiles({
    name: filename,
    mimeType: 'application/pdf',
    buffer: original,
  })
  const row = page.locator('.list-row').filter({ hasText: filename })
  await expect(row).toBeVisible()
  const id = await row.getAttribute('data-id')
  const url = await row.locator('a[target="_blank"]').getAttribute('href')
  await row.getByTestId('circle-dropdown-button').click()
  await page.getByRole('button', { name: 'Replace file', exact: true }).click()
  const dialog = page.getByRole('dialog', { name: 'Replace file', exact: true })
  await expect(dialog).toBeVisible()
  await expect(dialog.locator('.replacement-current .name')).toContainText(filename)
  await expect(dialog.locator('.replacement-current .updated')).toHaveText(url)
  return { row, id, url, dialog, original }
}

test('replaces a resource file while keeping its ID and download URL', async ({ page }, testInfo) => {
  await page.setViewportSize({ width: 1440, height: 1000 })
  const { row, id, url, dialog, original } = await uploadFile(page)
  await expect(page.locator('.progress-popup')).toHaveCount(0)
  await page.screenshot({ path: testInfo.outputPath('replace-file-dialog.png') })
  const replacement = Buffer.concat([original, Buffer.from('\n% Revised annual report\n')])
  await dialog.getByLabel('Replacement file').setInputFiles({
    name: 'revised-annual-report.pdf',
    mimeType: 'application/pdf',
    buffer: replacement,
  })
  await expect(dialog).not.toBeVisible()
  await expect(row).toHaveAttribute('data-id', id)
  await expect(row.locator('a[target="_blank"]')).toHaveAttribute('href', url)
  const download = await page.request.get(url)
  expect(download.status()).toBe(200)
  expect(await download.body()).toEqual(replacement)
  await expect(page.locator('.list-row')).toHaveCount(1)
  await expect(page.getByText('1 file', { exact: true })).toBeVisible()
  await expect(row).toContainText(`${replacement.length} B`)
  await expect(page.locator('.progress-popup')).toHaveCount(0)
  await page.screenshot({ path: testInfo.outputPath('replaced-file-listing.png') })
  await page.reload()
  await expect(row).toHaveAttribute('data-id', id)
  expect(await (await page.request.get(url)).body()).toEqual(replacement)
})

test('closing or rejecting a replacement keeps the original file', async ({ page }) => {
  const { row, url, dialog, original } = await uploadFile(page)
  await dialog.getByRole('button', { name: 'Close', exact: true }).click()
  await expect(dialog).not.toBeVisible()
  expect(await (await page.request.get(url)).body()).toEqual(original)

  await row.getByTestId('circle-dropdown-button').click()
  await page.getByRole('button', { name: 'Replace file', exact: true }).click()
  await dialog.getByLabel('Replacement file').setInputFiles({
    name: 'wrong-extension.txt',
    mimeType: 'text/plain',
    buffer: Buffer.from('This must not replace the PDF'),
  })
  await expect(page.locator('#brando-upload-manager')).toContainText('Choose a file with the same extension')
  expect(await (await page.request.get(url)).body()).toEqual(original)
  await expect(dialog).toBeVisible()
})
