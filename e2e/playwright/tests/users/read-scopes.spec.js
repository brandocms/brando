import { test, expect } from '../../test-support/setupAuth'
import { syncLV } from '../../utils'
import { e2eUrl } from '../../test-support/e2eUrl'

// An account that manages media and may read no pages sees that an asset is
// used, and by how many entries, without their names. The fixture's videos
// are used by two pages it cannot read.
test.skip(process.env.BRANDO_AUTHORIZATION_MODE !== 'groups', 'Requires explicit group mode')

test.use({ viewport: { width: 1440, height: 1000 } })

test('the video library counts entries the account cannot read, and sorts without naming them', async ({
  page,
  secondUserPage,
  sandboxUserAgent
}, testInfo) => {
  const fixtures = await page.request.post('/e2e/media-sweep-fixtures')
  expect(fixtures.ok(), await fixtures.text()).toBeTruthy()
  const { video_folder_id } = await fixtures.json()

  const grant = await fetch(e2eUrl('/e2e/authorization/media'), {
    method: 'POST',
    headers: { 'user-agent': sandboxUserAgent }
  })
  expect(grant.ok, await grant.text()).toBe(true)

  await secondUserPage.goto(`/admin/assets/videos?filter:folder_id=${video_folder_id}`)
  await syncLV(secondUserPage)
  await expect(secondUserPage.locator('.list-row')).toHaveCount(4)
  await expect(secondUserPage.locator('.usage-inline .usage-hidden')).toHaveCount(3)
  await expect(secondUserPage.locator('.list-row', { hasText: 'Spring campaign' })).toHaveCount(0)
  await secondUserPage.screenshot({ path: testInfo.outputPath('usage-inline.png') })

  await secondUserPage.locator('button[phx-click=sweep_open]').click()
  const dialog = secondUserPage.locator('#video-sweep')
  await expect(dialog.locator('.media-sweep-group')).toHaveCount(2)
  await expect(dialog.locator('.media-sweep-name')).toHaveCount(0)
  await expect(dialog).not.toContainText('Spring campaign')
  await expect(dialog).not.toContainText('Studio visits')
  await secondUserPage.screenshot({ path: testInfo.outputPath('sort-preview.png') })

  await dialog.locator('button[type=submit]').click()
  await expect(secondUserPage.getByTestId('sweep-result')).toBeVisible()
  await syncLV(secondUserPage)
  await secondUserPage.screenshot({ path: testInfo.outputPath('sorted.png') })
})
