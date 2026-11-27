import { test, expect } from '../../test-support/setupAuth'

// A video a template renders with `{% video %}` and no options is lazy
// (#4004): the server sends no `src` on the `<video>`, only `data-src`, and
// the site's video script (SmarterVideo) loads it on the public page. Live
// preview sets the source itself, so only a public page shows that the
// script does.
test('a lazy template video loads on the public page', async ({ page }) => {
  const response = await page.request.post('/e2e/setup_fixtures/template-video-page')
  expect(response.ok(), await response.text()).toBeTruthy()

  const html = await (await page.request.get('/template-video')).text()
  const served = html.match(/<video[^>]*data-video[^>]*>/)[0]
  expect(served).toContain('data-src="/media/videos/e2e-template-video.mp4"')
  expect(served).not.toMatch(/\ssrc=/)

  await page.goto('/template-video')
  const wrapper = page.locator('.template-video [data-smart-video]')
  await wrapper.scrollIntoViewIfNeeded()
  await expect(wrapper).toBeVisible()

  const video = wrapper.locator('video')
  await expect.poll(() => video.evaluate(el => el.currentSrc), { timeout: 15000 }).toContain(
    '/media/videos/e2e-template-video.mp4'
  )
})
