import { test, expect } from '../../test-support/setupAuth'
import { syncLV } from '../../utils'

// A video ref whose Bunny video is still encoding shows that it is, and takes
// the finished video from Bunny's webhook without a reload. Before, the ref
// kept a bare film icon until the entry was opened again. The fixture's page
// holds a Video Player block whose ref shows such a video; `/e2e/bunny/webhook`
// delivers Bunny's report for it, and the fake's thumbnail is answered here.

const BUNNY_CDN = 'https://bunny-cdn.e2e.test/**'

async function openProcessingRef(page) {
  const response = await page.request.post('/e2e/video-processing-fixtures')
  expect(response.ok(), await response.text()).toBeTruthy()
  const fixture = await response.json()
  expect((await page.request.post('/e2e/setup_fixtures/norwegian-admin-user')).ok()).toBe(true)

  await page.route(BUNNY_CDN, route => route.fulfill({ path: './fixtures/image.jpg', contentType: 'image/jpeg' }))
  await page.goto(`/admin/pages/update/${fixture.page_id}`)
  await syncLV(page)
  return fixture
}

async function report(page, videoGuid, status) {
  const response = await page.request.post('/e2e/bunny/webhook', { data: { video_guid: videoGuid, status } })
  expect(response.ok(), await response.text()).toBeTruthy()
}

const refCard = page => page.locator('.video-block [id$="-video-upload"]')

test('a video ref shows its video processing until Bunny reports it finished', async ({ page }, testInfo) => {
  const { video_guid: videoGuid } = await openProcessingRef(page)
  const card = refCard(page)

  await expect(card).toHaveAttribute('data-processing-video', 'true')
  await expect(card.getByRole('status').locator('.media-field-spinner')).toBeAttached()
  await expect(card.locator('.media-field-preview img')).toHaveCount(0)
  await card.screenshot({ path: testInfo.outputPath('video-ref-processing.png') })

  await report(page, videoGuid, 3)

  await expect(card).toHaveAttribute('data-processing-video', 'false')
  await expect(card.locator('.media-field-processing')).toHaveCount(0)
  await expect(card.locator('.media-field-meta')).toContainText('16:9')
  await expect(card.locator('.media-field-preview img')).toHaveAttribute('src', /bunny-cdn\.e2e\.test/)
  await card.screenshot({ path: testInfo.outputPath('video-ref-ready.png') })
})

test('a video ref shows a video Bunny failed to encode as failed', async ({ page }, testInfo) => {
  const { video_guid: videoGuid } = await openProcessingRef(page)
  const card = refCard(page)
  await expect(card).toHaveAttribute('data-processing-video', 'true')

  await report(page, videoGuid, 5)

  await expect(card).toHaveAttribute('data-processing-video', 'false')
  await expect(card.locator('.media-field-processing.is-failed')).toBeVisible()
  await card.screenshot({ path: testInfo.outputPath('video-ref-failed.png') })
})
