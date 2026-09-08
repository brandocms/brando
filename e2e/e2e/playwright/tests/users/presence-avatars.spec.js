import { test, expect } from '../../test-support/setupAuth'
import { syncLV } from '../../utils'

async function expectContainedPhoto(avatar) {
  const photo = avatar.locator('img')
  await expect(photo).toBeVisible()
  await expect.poll(() => photo.evaluate(img => img.naturalWidth)).toBeGreaterThan(0)
  // Check the rendered bounds, not just CSS declarations: an intrinsic-width
  // image wrapper used to escape the small flex avatar and cover the form.
  await expect.poll(() => avatar.evaluate(el => {
    const outer = el.getBoundingClientRect()
    const inner = el.querySelector('img').getBoundingClientRect()
    return inner.width > 0 && inner.height > 0 &&
      inner.left >= outer.left - 1 && inner.top >= outer.top - 1 &&
      inner.right <= outer.right + 1 && inner.bottom <= outer.bottom + 1
  })).toBe(true)
}

test('presence photos stay inside toolbar and field avatars through form patches', async ({ page, secondUserPage }, testInfo) => {
  await page.setViewportSize({ width: 1440, height: 1000 })
  await secondUserPage.setViewportSize({ width: 1440, height: 1000 })
  const response = await page.request.post('/e2e/user-directory/create')
  expect(response.ok()).toBe(true)
  const fixture = await response.json()
  try {
    await page.goto('/admin/pages/update/1')
    await syncLV(page)
    const toolbarAvatar = page.locator('.page-presences').getByRole('img', { name: 'Brando Admin', exact: true })
    await expectContainedPhoto(toolbarAvatar)
    await expect(toolbarAvatar).toHaveCSS('width', '30px')

    await secondUserPage.goto('/admin/pages/update/1')
    await syncLV(secondUserPage)
    const remoteToolbarAvatar = secondUserPage.locator('.page-presences').getByRole('img', { name: 'Brando Admin', exact: true })
    await expectContainedPhoto(remoteToolbarAvatar)
    await expect(secondUserPage.locator('.page-presences .avatar-placeholder')).toBeVisible()

    await page.getByLabel('Title', { exact: true }).click()
    const lockedField = secondUserPage.locator('.field-wrapper.field-locked')
    await expect(lockedField).toHaveCount(1)
    const fieldAvatar = lockedField.locator('.field-presence-user .avatar')
    await expectContainedPhoto(fieldAvatar)
    await expect(fieldAvatar).toHaveCSS('width', '14px')

    await secondUserPage.getByLabel('URI', { exact: true }).fill('presence-avatar-check')
    await syncLV(secondUserPage)
    await expectContainedPhoto(remoteToolbarAvatar)
    await expectContainedPhoto(fieldAvatar)
    await expect(secondUserPage.locator('body > canvas')).toBeHidden()
    await secondUserPage.screenshot({ path: testInfo.outputPath('presence-avatars-desktop.png'), fullPage: false })

  } finally {
    await page.request.post('/e2e/user-directory/cleanup', { data: fixture })
  }
})
