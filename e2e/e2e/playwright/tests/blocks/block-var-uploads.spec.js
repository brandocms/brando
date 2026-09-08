import { test, expect } from '../../test-support/setupAuth'
import { syncLV, confirmUploadFolder } from '../../utils'

async function createVarPage(page, title) {
  await page.goto('/admin/pages/create')
  await syncLV(page)
  await page.getByLabel('Title', { exact: true }).fill(title)
  await page.getByLabel('URI').fill(title.toLowerCase().replaceAll(' ', '-'))
  await page.getByRole('button', { name: 'Add block' }).click()
  await page.getByRole('button', { name: '07 VAR UPLOAD TEST' }).click()
  await page.getByRole('button', { name: 'Image and File Vars' }).click()
  await syncLV(page)
}

function mediaField(page, type) {
  return page.locator(`.media-field[data-kind="block_var"][id$="-${type}-media"]`)
}

for (const type of ['image', 'file']) {
  test(`${type} var uploads, configures, and persists through save`, async ({ page }) => {
    test.setTimeout(120000)
    const title = `Var ${type} Upload Test`
    await createVarPage(page, title)
    const field = mediaField(page, type)
    await expect(field.getByRole('button', { name: 'Upload', exact: true })).toBeVisible()
    await field.locator('input[type="file"]').setInputFiles(type === 'image' ? './fixtures/image.jpg' : './fixtures/test.pdf')
    if (type === 'image') await confirmUploadFolder(page)
    await expect(field).toHaveAttribute('data-asset-id', /\d+/, { timeout: 20000 })
    if (type === 'image') await expect(field.locator('img')).toBeVisible({ timeout: 20000 })
    await field.getByRole('button', { name: 'Configure', exact: true }).click()
    const modal = page.locator(`[id$="${type}-config"]:visible`)
    await expect(modal.locator('.media-field')).toHaveAttribute('data-asset-id', /\d+/)
    await modal.getByRole('button', { name: 'Done', exact: true }).click()
    await page.getByRole('button', { name: 'Save', exact: true }).click()
    await syncLV(page)
    await expect(page).not.toHaveURL(/\/create$/, { timeout: 10000 })
    await page.getByRole('link', { name: title, exact: true }).click()
    await syncLV(page)
    await expect(mediaField(page, type)).toHaveAttribute('data-asset-id', /\d+/, { timeout: 20000 })
  })

  test(`${type} var removal leaves a usable upload field`, async ({ page }) => {
    test.setTimeout(120000)
    await createVarPage(page, `Var ${type} Remove Test`)
    const field = mediaField(page, type)
    await field.locator('input[type="file"]').setInputFiles(type === 'image' ? './fixtures/image.jpg' : './fixtures/test.pdf')
    if (type === 'image') await confirmUploadFolder(page)
    await expect(field).toHaveAttribute('data-asset-id', /\d+/, { timeout: 20000 })
    await field.getByRole('button', { name: 'Configure', exact: true }).click()
    const modal = page.locator(`[id$="${type}-config"]:visible`)
    await modal.getByRole('button', { name: 'Remove', exact: true }).click()
    await modal.getByRole('button', { name: 'Done', exact: true }).click()
    await expect(modal).not.toBeVisible()
    await expect(field).not.toHaveAttribute('data-asset-id', /\d+/)
    await expect(field.getByRole('button', { name: 'Upload', exact: true })).toBeVisible()
    await expect(field.getByRole('button', { name: 'Browse library', exact: true })).toBeVisible()
  })
}
