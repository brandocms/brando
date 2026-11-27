import { test, expect } from '../../test-support/setupAuth'

// A video block with a cover, a play button and a caption on a public page.
// SmarterVideo hands the <video> to Vidstack, which wraps it in a
// <media-player>: the cover and button must sit on that, the caption below.
test.beforeEach(async ({ page }) => {
  const response = await page.request.post('/e2e/setup_fixtures/captioned-video-page')
  expect(response.ok(), await response.text()).toBeTruthy()

  await page.goto('/captioned-video')
  const wrapper = page.locator('.captioned-video [data-smart-video]')
  await wrapper.scrollIntoViewIfNeeded()
  await expect(wrapper).toHaveAttribute('data-can-play')
  await expect(wrapper.locator('media-player')).toHaveCount(1)
})

test('the cover and play button sit on the video once the player starts, the caption below', async ({ page }) => {
  const wrapper = page.locator('.captioned-video [data-smart-video]')

  const player = await wrapper.locator('media-player').boundingBox()
  const cover = await wrapper.locator('[data-cover]').boundingBox()
  const button = await wrapper.locator('.video-play-button-wrapper').boundingBox()
  const caption = await wrapper.locator('figcaption').boundingBox()

  expect(cover).toEqual(player)
  expect(button.y + button.height / 2).toBeCloseTo(player.y + player.height / 2, 0)
  expect(caption.y).toBeGreaterThanOrEqual(player.y + player.height)
})
