import { test, expect } from '../test-support/setupAuth'
import { syncLV } from '../utils'

// Background work (BrandoAdmin.Work) reports to the user who started it: one
// toast per work, updated in place, except on a screen that shows the work
// itself. `/e2e/work/:action` reports as a job would. The work registry is
// outside the SQL sandbox, so each test ends the work it started.
//
// The setup hides `.toast-stack`; the toasts are asserted by their content.

async function report(page, action, data) {
  expect((await page.request.post(`/e2e/work/${action}`, { data })).ok()).toBe(true)
}

// A live navigation, which keeps the page and its toasts
async function navigate(page, href) {
  await page.evaluate((to) => {
    window.liveSocket.execJS(document.body, JSON.stringify([['navigate', { href: to }]]))
  }, href)
  await expect(page).toHaveURL(href)
  await syncLV(page)
}

test('work shows as one toast, updated in place until it ends', async ({ page }) => {
  const key = `e2e-import-${Date.now()}`

  try {
    // Running before the page loads: the toast comes with the user channel's join
    await report(page, 'start', { key, message: 'Importing products', total: 2 })
    await page.goto('/admin')
    await syncLV(page)

    const toast = page.locator(`.toast[data-work-id="${key}"]`)
    await expect(toast).toHaveCount(1)
    await expect(toast).toHaveClass(/toast--work/)
    await expect(toast).toContainText('Importing products')
    await expect(toast.locator('.toast-count')).toHaveText('0 / 2')
    await expect(toast.locator('.toast-progress')).toHaveAttribute('aria-valuenow', '0')

    await report(page, 'advance', { key })
    await expect(toast.locator('.toast-count')).toHaveText('1 / 2')
    await expect(toast.locator('.toast-progress')).toHaveAttribute('aria-valuenow', '50')
    await expect(toast).toHaveCount(1)

    await report(page, 'finish', { key, message: 'Products imported' })
    await expect(toast).toHaveClass(/toast--success/)
    await expect(toast).toContainText('Products imported')
    await expect(toast.locator('.toast-count')).toHaveCount(0)
    await expect(page.locator('.toast-stack .toast')).toHaveCount(1)
  } finally {
    await report(page, 'finish', { key })
  }
})

test('a failure stays as an error toast', async ({ page }) => {
  const key = `e2e-fail-${Date.now()}`
  await report(page, 'start', { key, message: 'Fetching policies' })
  await page.goto('/admin')
  await syncLV(page)

  const toast = page.locator(`.toast[data-work-id="${key}"]`)
  await expect(toast).toContainText('Fetching policies')

  await report(page, 'fail', { key, message: 'Could not fetch the policies' })
  await expect(toast).toHaveClass(/toast--error/)
  await expect(toast).toContainText('Could not fetch the policies')
})

test('the screen that shows the work takes over from its toast', async ({ page }) => {
  const key = 'video-metadata'

  try {
    await report(page, 'start', { key, message: 'Looking up 3 videos', total: 3 })

    // The video library shows the lookups beside its button, so no toast
    await page.goto('/admin/assets/videos')
    await syncLV(page)
    const status = page.locator(`.work-status[data-work-id="${key}"]`)
    await expect(status).toHaveAttribute('data-status', 'running')
    await expect(status).toContainText('Looking up 3 videos')
    await expect(status.locator('.work-count')).toHaveText('0 / 3')
    await expect(page.locator('button[phx-click="fetch_metadata"]')).toBeDisabled()

    await report(page, 'advance', { key })
    await expect(status.locator('.work-count')).toHaveText('1 / 3')
    await expect(page.locator(`.toast[data-work-id="${key}"]`)).toHaveCount(0)

    // Leaving it brings the toast, and coming back takes it away again
    await navigate(page, '/admin')
    const toast = page.locator(`.toast[data-work-id="${key}"]`)
    await expect(toast).toHaveCount(1)
    await expect(toast.locator('.toast-count')).toHaveText('1 / 3')

    await navigate(page, '/admin/assets/videos')
    await expect(status.locator('.work-count')).toHaveText('1 / 3')
    await expect(toast).toHaveCount(0)

    // The end shows where the work is shown
    await report(page, 'finish', { key, message: 'Thumbnails and titles fetched' })
    await expect(status).toHaveAttribute('data-status', 'finished')
    await expect(status).toContainText('Thumbnails and titles fetched')
    await expect(toast).toHaveCount(0)
  } finally {
    await report(page, 'finish', { key })
  }
})
