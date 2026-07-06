import { test, expect } from '../../test-support/setupAuth'
import { syncLV } from '../../utils'

test('seo changes affect the frontpage', async ({ page }) => {
  await page.goto('/admin')
  await page.getByText('Configuration').click()
  await page.getByRole('link', { name: 'SEO' }).click()
  await expect(page).toHaveURL('/admin/config/seo')
  await syncLV(page)
  await page.getByLabel('Fallback META title').fill('Brando CMS')
  await page.getByLabel('Fallback META description').fill('Brando CMS: A CMS of sorts.')
  await page.getByPlaceholder('https://yoursite.com').fill('https://brando.dev')
  await page.locator('textarea[name="seo[robots]"]').fill('User-agent: *\nDisallow: /secret')
  await page.getByRole('button', { name: 'Add entry' }).click()
  await page.locator('input[name="seo[redirects][0][code]"]').click()
  await page.locator('input[name="seo[redirects][0][code]"]').fill('301')
  // Add SEO image
  await page.getByRole('button', { name: 'Add image' }).click()
  await page.locator('#image-drawer-upload-input').setInputFiles('./fixtures/image.jpg')
  // Wait for upload to complete - the image should appear in the drawer
  await expect(page.locator('#image-drawer img')).toBeVisible({ timeout: 30000 })
  // Close drawer - this should save the image selection
  await page.getByRole('button', { name: 'Close' }).click()
  await page.waitForSelector('#image-drawer', { state: 'hidden' })
  await syncLV(page)
  await expect(page.getByText('No image associated with')).toHaveCount(0)
  await page.getByTestId('submit').click()
  await expect(page).toHaveURL('/admin/config/seo')
  await syncLV(page)

  // Wait for the cache to be updated
  // The SEO update happens through Cachex and needs time to propagate
  await page.waitForTimeout(500)

  // test meta tags - go to homepage and wait for full load
  await page.goto('/', { waitUntil: 'networkidle' })

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
