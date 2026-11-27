import { test, expect } from '@playwright/test'
import { fileURLToPath } from 'node:url'

// The files seed_video.exs points the about page's video blocks at
const src = 'https://media.smoke.test/clip.webm'
const coverSrc = 'https://media.smoke.test/cover.webm'
const clip = fileURLToPath(new URL('clip.webm', import.meta.url))

const playing = video => video.evaluate(el => !el.paused && el.currentTime > 0)

test.beforeEach(async ({ page }) => {
  for (const url of [src, coverSrc]) {
    await page.route(url, route => route.fulfill({ path: clip, contentType: 'video/webm' }))
  }
})

test('a video block on a public page is revealed, gets its source and plays', async ({ page }) => {
  const errors = []
  page.on('pageerror', error => errors.push(error.message))

  await page.goto('/about')
  const wrapper = page.locator('main [data-smart-video]').first()
  const video = wrapper.locator('video')

  // Brando renders it lazy, the installed CSS hides it, and the frontend's
  // SmartVideo sets the source and reveals it.
  await expect(wrapper).toHaveAttribute('data-preload', src)
  await expect(wrapper).toBeVisible()
  await expect(wrapper).toHaveCSS('opacity', '1')
  await expect(video).toHaveJSProperty('currentSrc', src)
  await expect.poll(() => playing(video)).toBe(true)
  expect(errors).toEqual([])
})

test('the cover and play button of a video block sit on the video, its caption below', async ({ page }) => {
  await page.goto('/about')
  const wrapper = page.locator('main [data-smart-video]').last()
  await wrapper.scrollIntoViewIfNeeded()
  await expect(wrapper).toHaveCSS('opacity', '1')

  const video = await wrapper.locator('video').boundingBox()
  const cover = await wrapper.locator('[data-cover]').boundingBox()
  const button = await wrapper.locator('.video-play-button-wrapper').boundingBox()
  const caption = await wrapper.locator('figcaption').boundingBox()

  expect(cover).toEqual(video)
  expect(button.y + button.height / 2).toBeCloseTo(video.y + video.height / 2, 0)
  expect(caption.y).toBeGreaterThanOrEqual(video.y + video.height)
})

test('the play button of a video block with a cover plays it and hides the cover', async ({ page }) => {
  await page.goto('/about')
  const wrapper = page.locator('main [data-smart-video]').last()
  const video = wrapper.locator('video')
  const cover = wrapper.locator('[data-cover]')

  await expect(wrapper).toHaveAttribute('data-preload', coverSrc)
  await wrapper.scrollIntoViewIfNeeded()
  await expect(wrapper).toHaveCSS('opacity', '1')
  await expect(cover).toBeVisible()
  await expect(video).toHaveJSProperty('paused', true)

  await wrapper.getByRole('button').click()
  await expect.poll(() => playing(video)).toBe(true)
  await expect(cover).toBeHidden()
})
