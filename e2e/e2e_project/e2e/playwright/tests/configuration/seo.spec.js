import { test, expect } from '../../test-support/setupAuth'
import { syncLV } from '../../utils'

//
// TODO:
// - Add test for SEO image, currently fails..
//

test('seo changes affect the frontpage', async ({ page }) => {
  await page.goto('/admin')
  await page.getByText('Configuration').click()
  await page.getByRole('link', { name: 'SEO' }).click()
  await expect(page).toHaveURL('/admin/config/seo')
  await syncLV(page)
  await page.getByLabel('Fallback META title').fill('Brando CMS')
  await page
    .getByLabel('Fallback META description')
    .fill('Brando CMS: A CMS of sorts.')
  await page.getByPlaceholder('https://yoursite.com').fill('https://brando.dev')
  await page
    .locator('textarea[name="seo[robots]"]')
    .fill('User-agent: *\nDisallow: /secret')
  await page.getByRole('button', { name: 'Add entry' }).click()
  await page.locator('input[name="seo[redirects][0][code]"]').click()
  await page.locator('input[name="seo[redirects][0][code]"]').fill('301')
  // Add SEO image
  await page.getByRole('button', { name: 'Add image' }).click()
  await page
    .locator('input[name="fallback_meta_image"]')
    .setInputFiles('./fixtures/image.jpg')
  // Close drawer
  await page.getByRole('button', { name: 'Close' }).click()
  // Wait for the drawer to vanish or the form to be detached
  await page.waitForSelector('#image-drawer', { state: 'hidden' })
  await page.evaluate(() => {
    document
      .querySelector('#image-drawer-form')
      .dispatchEvent(new Event('submit', { bubbles: true, cancelable: true }))
  })

  // Or run your syncLV function again (if you have a helper that
  // ensures the LiveView socket is in sync)
  await syncLV(page)

  await expect(page.getByText('No image associated with')).toHaveCount(0)
  await page.getByTestId('submit').click()
  await syncLV(page)
  await expect(page).toHaveURL('/admin/config/seo')

  // test meta tags
  await page.goto('/')
  const metaDescriptionLocator = page.locator('meta[name="description"]')
  const metaDescription = await metaDescriptionLocator.getAttribute('content')
  expect(metaDescription).toBe('Brando CMS: A CMS of sorts.')

  const metaTitleLocator = page.locator('meta[name="title"]')
  const metaTitle = await metaTitleLocator.getAttribute('content')
  expect(metaTitle).toBe('Index')

  // test robots
  let response = await page.request.get('/robots.txt')
  const robotsText = await response.text()
  expect(robotsText).toContain('User-agent: *\nDisallow: /secret')

  // test redirects
  response = await page.request.get('/example/redirect', { maxRedirects: 0 })

  // Assert the HTTP status is 301
  expect(response.status()).toBe(301)

  // Assert the Location header
  const locationHeader = response.headers()['location']
  expect(locationHeader).toBe('/new/redirect')
})
