import { test, expect } from '../../test-support/setupAuth'
import { syncLV, confirmUploadFolder } from '../../utils'

// Visibility/bounding boxes alone pass for menus clipped by overflow: clip.
// Check the actual hit targets at both edges of every action as well.
async function expectUnclipped(menu) {
  await expect(menu).toBeVisible()
  await expect(async () => {
    const result = await menu.evaluate(el => {
      const rect = el.getBoundingClientRect()
      return {
        inViewport: rect.left >= 0 && rect.top >= 0 && rect.right <= innerWidth && rect.bottom <= innerHeight,
        actionsReachable: [...el.querySelectorAll('button')].every(button => {
          const box = button.getBoundingClientRect()
          return [box.top + 3, box.bottom - 3].every(y =>
            button.contains(document.elementFromPoint(box.x + box.width / 2, y)))
        }),
      }
    })
    expect(result).toEqual({ inViewport: true, actionsReachable: true })
  }).toPass()
}

for (const [type, module, file] of [
  ['image', 'Single Image with Caption', 'image.jpg'],
  ['video', 'Video Player', 'video.mp4'],
  ['file', 'Media attachment', 'test.pdf'],
]) {
  test(`${type} ref replacement escapes clipping and works at desktop and mobile widths`, async ({ page }, testInfo) => {
    test.setTimeout(120000)
    await page.setViewportSize({ width: 1440, height: 1000 })
    if (type === 'file') {
      const response = await page.request.post('/e2e/setup_fixtures/media-upload')
      expect(response.ok()).toBe(true)
    }
    await page.goto('/admin/pages/create')
    await syncLV(page)
    await page.getByLabel('Title', { exact: true }).fill(`${type} dropdown`)
    await page.getByRole('button', { name: 'Add block', exact: true }).click()
    await page.getByRole('button', { name: '05 LIVE PREVIEW TEST' }).click()
    await page.getByRole('button', { name: module, exact: true }).click()
    const field = page.locator(`.${type === 'image' ? 'picture' : type}-block .media-field--block:visible`)
    await field.locator('input[type=file]').setInputFiles(`./fixtures/${file}`)
    if (type === 'image') await confirmUploadFolder(page)
    await expect(field).toHaveAttribute('data-asset-id', /\d+/, { timeout: 30000 })
    if (type === 'image') await expect(field.locator('img')).toBeVisible({ timeout: 30000 })

    const trigger = field.getByRole('button', { name: 'Replace', exact: true })
    const menu = field.locator('.media-field-menu')
    for (const width of [1440, 390]) {
      await page.setViewportSize({ width, height: 844 })
      await trigger.click()
      await expectUnclipped(menu)
      await page.screenshot({ path: testInfo.outputPath(`${type}-replace-${width}.png`) })
      await page.keyboard.press('Escape')
      await expect(menu).not.toBeVisible()
      await expect(trigger).toBeFocused()

      await trigger.press('Space')
      await expectUnclipped(menu)
      await menu.getByRole('button', { name: 'Browse library', exact: true }).click()
      const picker = page.locator(`#${type}-picker`)
      await expect(picker).toBeVisible()
      await expect(menu).not.toBeVisible()
      await page.keyboard.press('Escape')
      await expect(picker).not.toBeVisible()
      await expect(trigger).toBeFocused()
    }

    // A real replacement must still reach this ref's UploadTrigger owner.
    const originalId = await field.getAttribute('data-asset-id')
    await trigger.click()
    const chooser = page.waitForEvent('filechooser')
    await menu.getByRole('button', { name: 'Upload replacement', exact: true }).click()
    await (await chooser).setFiles(`./fixtures/${file}`)
    if (type === 'image') await confirmUploadFolder(page)
    await expect(menu).not.toBeVisible()
    await expect(field).not.toHaveAttribute('data-asset-id', originalId, { timeout: 30000 })

    if (type === 'image') {
      await field.getByRole('button', { name: 'Configure', exact: true }).click()
      const modal = page.getByRole('dialog', { name: 'Configure image', exact: true })
      await modal.getByRole('tab', { name: 'Image', exact: true }).click()
      const modalTrigger = modal.getByRole('button', { name: 'Replace', exact: true })
      const modalMenu = modal.locator('.media-field-menu')
      await modalTrigger.click()
      await expectUnclipped(modalMenu)
      await page.keyboard.press('Escape')
      await expect(modalMenu).not.toBeVisible()
      await expect(modal).toBeVisible()
      await expect(modalTrigger).toBeFocused()
    }
  })
}

test('image drawer menus follow scrolling, flip at the viewport edge and dismiss independently', async ({ page }, testInfo) => {
  await page.setViewportSize({ width: 1440, height: 1000 })
  await page.goto('/admin/projects/projects/update/3')
  await syncLV(page)
  const field = page.locator('#project_listing_image-media')
  await field.locator('input[type=file]').setInputFiles('./fixtures/image.jpg')
  await confirmUploadFolder(page)
  await expect(field.locator('img')).toBeVisible({ timeout: 30000 })
  await field.getByRole('button', { name: 'Configure', exact: true }).click()
  const drawer = page.getByRole('dialog', { name: 'Image details', exact: true })
  const replace = drawer.getByRole('button', { name: 'Replace', exact: true })
  const menu = drawer.locator('#image-drawer-replace-menu')
  await replace.click()
  await expectUnclipped(menu)
  await drawer.getByRole('button', { name: 'More image actions', exact: true }).click()
  await expect(menu).not.toBeVisible()
  const more = drawer.locator('#image-drawer-more-menu')
  await expectUnclipped(more)
  await page.keyboard.press('Escape')
  await expect(more).not.toBeVisible()
  await expect(drawer).toBeVisible()

  await page.setViewportSize({ width: 390, height: 500 })
  await replace.evaluate(el => el.scrollIntoView({ block: 'end' }))
  await replace.click()
  await expectUnclipped(menu)
  const triggerBox = await replace.boundingBox()
  const menuBox = await menu.boundingBox()
  expect(menuBox.y + menuBox.height).toBeLessThanOrEqual(triggerBox.y)
  await page.screenshot({ path: testInfo.outputPath('image-drawer-replace-mobile.png') })
  await drawer.locator('.drawer-form').evaluate(el => { el.scrollTop += 35 })
  await expectUnclipped(menu)
  await expect(async () => {
    const triggerBox = await replace.boundingBox()
    const menuBox = await menu.boundingBox()
    const aboveGap = triggerBox.y - menuBox.y - menuBox.height
    const belowGap = menuBox.y - triggerBox.y - triggerBox.height
    expect(Math.min(Math.abs(aboveGap - 5), Math.abs(belowGap - 5))).toBeLessThanOrEqual(1)
  }).toPass()
  await drawer.getByRole('button', { name: 'Done', exact: true }).click()
  await expect(drawer).not.toBeVisible()
  await expect(menu).not.toBeVisible()
})
