import { test, expect } from '../../test-support/setupAuth'
import { syncLV } from '../../utils'

// Delete in a picker row's menu asks first. Cancelling leaves the image and
// the menu as they were, and the keyboard stays in the picker: Escape closes
// the menu, Tab walks the picker and Escape again closes it.
test('cancelling a delete in the image picker keeps focus in the picker', async ({ page }) => {
  const response = await page.request.post('/e2e/alt-text-image')
  expect(response.ok()).toBe(true)
  const { id: imageId } = await response.json()

  // Where the keyboard is: in the picker, or the tag it fell to
  const focusedIn = () =>
    page.evaluate(() => (document.activeElement?.closest('#image-picker') ? '#image-picker' : document.activeElement?.tagName))

  await page.setViewportSize({ width: 1440, height: 1000 })
  await page.goto('/admin/pages/update/1')
  await syncLV(page)

  await page.locator('.form-tool-meta').click()
  await page.locator('#page_meta_image-media').getByRole('button', { name: 'Select image', exact: true }).click()

  const picker = page.getByRole('dialog', { name: 'Images', exact: true })
  await expect(picker).toBeVisible()
  await picker.getByRole('button', { name: 'Root', exact: true }).click()
  const row = picker.locator(`.image-picker__image[data-id="${imageId}"]`)
  await expect(row).toBeVisible()

  const toggle = row.getByRole('button', { name: 'Image actions', exact: true })
  await toggle.click()
  const deleteItem = row.getByRole('button', { name: 'Delete image', exact: true })
  await expect(deleteItem).toBeVisible()
  await deleteItem.click()

  const confirm = page.locator('dialog.admin-dialog[open]')
  await expect(confirm.getByRole('heading', { name: 'Delete this image?' })).toBeVisible()
  await confirm.getByRole('button', { name: 'Cancel', exact: true }).click()
  await expect(confirm).toHaveCount(0)
  await syncLV(page)

  // The menu it was asked from is still open, with the Delete item focused
  await expect(row).toBeVisible()
  await expect(deleteItem).toBeFocused()
  await expect.poll(focusedIn).toBe('#image-picker')

  await page.keyboard.press('Escape')
  await expect(deleteItem).toBeHidden()
  await expect(toggle).toBeFocused()

  await page.keyboard.press('Tab')
  await expect.poll(focusedIn).toBe('#image-picker')

  await page.keyboard.press('Escape')
  await expect(picker).not.toBeVisible()
})
