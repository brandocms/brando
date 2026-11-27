import { test, expect } from '@playwright/test'
import { fileURLToPath } from 'node:url'

// The file seed_video.exs points the about page's video block at
const src = 'https://media.smoke.test/clip.webm'
const clip = fileURLToPath(new URL('clip.webm', import.meta.url))

test('a video block on a public page is revealed, gets its source and plays', async ({ page }) => {
  const errors = []
  page.on('pageerror', error => errors.push(error.message))
  await page.route(src, route => route.fulfill({ path: clip, contentType: 'video/webm' }))

  await page.goto('/about')
  const wrapper = page.locator('main [data-smart-video]')
  const video = wrapper.locator('video')

  // Brando renders it lazy, the installed CSS hides it, and the frontend's
  // SmartVideo sets the source and reveals it.
  await expect(wrapper).toHaveAttribute('data-preload', src)
  await expect(wrapper).toBeVisible()
  await expect(video).toHaveJSProperty('currentSrc', src)
  await expect.poll(() => video.evaluate(el => !el.paused && el.currentTime > 0)).toBe(true)
  expect(errors).toEqual([])
})
