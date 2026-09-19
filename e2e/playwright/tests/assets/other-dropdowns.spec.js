import { test, expect } from '../../test-support/setupAuth'
import { syncLV, confirmUploadFolder } from '../../utils'

async function checkMenu(page, trigger, menu, testInfo, name) {
  await trigger.evaluate(el => el.scrollIntoView({ block: 'end' }))
  await trigger.click()
  await expect(menu).toBeVisible()
  await page.waitForTimeout(350)
  const result = await menu.evaluate(el => {
    const rect = el.getBoundingClientRect()
    const actions = [...el.querySelectorAll('button, a, label')]
    return {
      inViewport: rect.left >= 0 && rect.top >= 0 && rect.right <= innerWidth && rect.bottom <= innerHeight,
      obscured: actions.filter(action => {
        const r = action.getBoundingClientRect()
        return !r.height || ![r.top + 2, r.bottom - 2].every(y => action.contains(document.elementFromPoint(r.x + r.width / 2, y)))
      }).map(action => action.textContent.trim()),
    }
  })
  await page.screenshot({ path: testInfo.outputPath(`${name}.png`) })
  expect.soft(result, name).toEqual({ inViewport: true, obscured: [] })
  await trigger.click()
  await expect(menu).not.toBeVisible()
}

test('block and block-field actions stay reachable inside containers', async ({ page }, testInfo) => {
  await page.setViewportSize({ width: 1440, height: 844 })
  await page.goto('/admin/pages/create')
  await syncLV(page)
  await page.getByLabel('Title', { exact: true }).fill('Dropdown container')
  await page.getByLabel('URI', { exact: true }).fill('dropdown-container')
  await page.getByRole('button', { name: 'Add block', exact: true }).click()
  await page.getByRole('button', { name: 'Container', exact: true }).click()
  const container = page.locator('[data-block-type="container"]')
  await checkMenu(page, container.locator('.block-action-dropdown > button').first(), container.locator('.block-action-dropdown-content').first(), testInfo, 'empty-container')
  await container.locator('.block-plus').first().click()
  await page.getByRole('button', { name: /HEADERS/ }).click()
  await page.getByRole('button', { name: /^Heading\b/ }).click()
  const child = container.locator('.block-children > [data-uid]').first()
  for (const width of [1440, 390]) {
    await page.setViewportSize({ width, height: 844 })
    await checkMenu(page, child.locator('.block-action-dropdown > button').first(), child.locator('.block-action-dropdown-content').first(), testInfo, `nested-block-${width}`)
    await checkMenu(page, page.locator('.block-field-dropdown-toggle').first(), page.locator('.block-field-dropdown-content').first(), testInfo, `block-field-${width}`)
  }
})

test('listing action, sort and status menus fit the viewport', async ({ page }, testInfo) => {
  await page.goto('/admin/pages')
  await syncLV(page)
  for (const width of [1440, 390]) {
    await page.setViewportSize({ width, height: 600 })
    const row = page.locator('.list-row').last()
    await checkMenu(page, row.getByTestId('circle-dropdown-button'), row.getByTestId('circle-dropdown-content'), testInfo, `listing-actions-${width}`)
    await checkMenu(page, row.locator('.status > div:has(> .status-dropdown)'), row.locator('.status-dropdown'), testInfo, `listing-status-${width}`)
    await checkMenu(page, page.locator('.sorts .simple-dropdown-button'), page.locator('.sorts .simple-dropdown-content'), testInfo, `listing-sort-${width}`)
  }
  const row = page.locator('.list-row').last()
  await row.locator('.listing-creator').click({ modifiers: ['Shift'] })
  const selected = page.locator('.selected-rows')
  await checkMenu(page, selected.getByTestId('circle-dropdown-button'), selected.getByTestId('circle-dropdown-content'), testInfo, 'selected-actions-390')
  await selected.getByRole('button', { name: 'Clear selection', exact: true }).click()
})

test('nested status and toolbar menus fit narrow editors', async ({ page }, testInfo) => {
  await page.goto('/admin/config/navigation/menus/update/1')
  await syncLV(page)
  for (const width of [1440, 390]) {
    await page.setViewportSize({ width, height: 600 })
    const row = page.locator('.subform-entry').last()
    await checkMenu(page, row.locator('.status-trigger').first(), row.locator('.status-dropdown').first(), testInfo, `subform-status-${width}`)
  }
  const statusRow = page.locator('.subform-entry').last()
  await statusRow.locator('.status-trigger').first().click()
  const statusMenu = statusRow.locator('.status-dropdown').first()
  const nextStatus = await statusMenu.getByLabel('Published', { exact: true }).isChecked() ? 'Draft' : 'Published'
  await statusMenu.getByLabel(nextStatus, { exact: true }).check()
  await syncLV(page)
  await expect(statusRow.locator('.status-dropdown').first()).not.toBeVisible()
  await expect(statusRow.locator('.status-trigger').first()).toHaveAttribute('aria-expanded', 'false')
  await statusRow.locator('.status-trigger').first().click()
  await expect(statusMenu.getByLabel(nextStatus, { exact: true })).toBeChecked()
  await page.keyboard.press('Escape')
  await expect(statusRow.locator('.status-trigger').first()).toBeFocused()
  await page.goto('/admin/pages/update/1')
  await syncLV(page)
  for (const width of [1440, 390]) {
    await page.setViewportSize({ width, height: 600 })
    await checkMenu(page, page.getByTestId('split-dropdown-button'), page.getByTestId('split-dropdown-content'), testInfo, `save-${width}`)
    await checkMenu(page, page.locator('.preview-chooser-trigger'), page.locator('.preview-choices'), testInfo, `preview-${width}`)
  }
})

test('revision action menus escape the drawer table and Escape keeps the drawer open', async ({ page }, testInfo) => {
  await page.setViewportSize({ width: 1440, height: 844 })
  await page.goto('/admin/pages/update/1')
  await syncLV(page)
  await page.getByRole('button', { name: 'Revisions', exact: true }).click()
  const drawer = page.locator('[id$="-revisions-drawer"]')
  await drawer.getByRole('button', { name: 'Store current editor state', exact: true }).click()
  const row = drawer.locator('[id^="revision-line-"]').first()
  await expect(row).toBeVisible()
  for (const width of [1440, 390]) {
    await page.setViewportSize({ width, height: 600 })
    await checkMenu(page, row.getByTestId('circle-dropdown-button'), row.getByTestId('circle-dropdown-content'), testInfo, `revision-actions-${width}`)
  }
  const trigger = row.getByTestId('circle-dropdown-button')
  await trigger.click()
  await page.keyboard.press('Escape')
  await expect(row.getByTestId('circle-dropdown-content')).not.toBeVisible()
  await expect(drawer).toBeVisible()
  await expect(trigger).toBeFocused()
})

test('image and video picker action menus escape scrolling rows', async ({ page }, testInfo) => {
  await page.setViewportSize({ width: 1440, height: 844 })
  await page.goto('/admin/projects/projects/update/3')
  await syncLV(page)
  for (const [type, fieldId, file] of [['image', 'project_listing_image', 'image.jpg'], ['video', 'project_cover_video', 'video.mp4']]) {
    const field = page.locator(`#${fieldId}-media`)
    await field.locator('input[type=file]').setInputFiles(`./fixtures/${file}`)
    if (type === 'image') await confirmUploadFolder(page)
    await expect(field).toHaveAttribute('data-asset-id', /\d+/, { timeout: 30000 })
    await field.getByRole('button', { name: 'Browse library', exact: true }).click()
    const picker = page.locator(`#${type}-picker`)
    await picker.getByRole('button', { name: 'List', exact: true }).click()
    for (const width of [1440, 390]) {
      await page.setViewportSize({ width, height: 600 })
      const row = picker.locator(`.${type}-picker__${type}`).last()
      await checkMenu(page, row.getByRole('button', { name: `${type === 'image' ? 'Image' : 'Video'} actions`, exact: true }), row.locator(`.${type}-picker-action-dropdown`), testInfo, `${type}-picker-${width}`)
    }
    await picker.getByRole('button', { name: 'Close', exact: true }).click()
    await page.setViewportSize({ width: 1440, height: 844 })
  }
})
