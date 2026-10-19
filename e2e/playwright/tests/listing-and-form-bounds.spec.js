import { test, expect } from '../test-support/setupAuth'
import { syncLV, waitForPreviewReady } from '../utils'

// On a wide screen an entry form stops at 1400px, as a listing stops at
// 1280px, and lifts the bound while the live preview takes the right side
// (Form.css, the LivePreview hook). A listing's column headings, rows and
// footer sit in one bordered frame (list.html.heex, Users.css).

const width = locator => locator.evaluate(el => Math.round(el.getBoundingClientRect().width))

test('an entry form is bounded until the live preview opens, and again once it closes', async ({ page }) => {
  await page.setViewportSize({ width: 2200, height: 1100 })
  await page.goto('/admin/pages/update/1')
  await syncLV(page)

  const content = page.locator('.brando-form .form-content').first()
  await expect.poll(() => width(content)).toBe(1400)

  await page.locator('.live-preview-toggle').click()
  await page.locator('.preview-choice').first().click()
  await waitForPreviewReady(page)
  await expect(page.locator('.brando-form').first()).toHaveClass(/is-previewing/)
  // The form takes everything up to the preview
  await expect.poll(() => width(content)).toBeGreaterThan(1400)

  await page.locator('.live-preview-close').click()
  await expect(page.locator('.live-preview')).toHaveCount(0)
  await expect(page.locator('.brando-form').first()).not.toHaveClass(/is-previewing/)
  await expect.poll(() => width(content)).toBe(1400)
})

test("a listing's rows and footer share one frame", async ({ page }) => {
  await page.setViewportSize({ width: 1440, height: 900 })
  await page.goto('/admin/pages')
  await syncLV(page)

  const frame = page.locator('.content-list-frame')
  await expect(frame).toHaveCount(1)
  await expect(frame.locator('> .sort-container .list-row').first()).toBeVisible()
  await expect(frame.locator('> .pagination')).toBeVisible()
  await expect(frame).toHaveCSS('border-top-width', '1px')
  await expect(frame).toHaveCSS('border-radius', '6px')

  // A row's menu opens past the frame rather than being cut off by it
  const last = frame.locator('.list-row').last()
  await last.locator('.circle-dropdown-button').click()
  const menu = last.locator('.dropdown-content')
  await expect(menu).toBeVisible()
  await expect(menu.getByText('Edit', { exact: true })).toBeInViewport()
})

test('with the form at its bound, the notes panel sits at the right edge', async ({ page }) => {
  await page.setViewportSize({ width: 2200, height: 1100 })
  await page.goto('/admin/pages/update/1')
  await syncLV(page)

  await page.locator('.form-tool-notes').click()
  const panel = page.locator('.notes-panel.is-open .notes-panel-inner')
  await expect(panel).toBeVisible()
  await expect.poll(() => width(page.locator('.brando-form .form-content').first())).toBe(1400)
  await expect.poll(() => panel.evaluate(el => Math.round(innerWidth - el.getBoundingClientRect().right))).toBeLessThanOrEqual(1)
})

test("an empty listing's message keeps to the frame's border", async ({ page }) => {
  await page.setViewportSize({ width: 1440, height: 900 })
  await page.goto('/admin/projects/categories?status=deleted')
  await syncLV(page)

  const empty = page.locator('.content-list-frame :is(.workspace-empty, .empty-list)')
  await expect(empty).toBeVisible()
  await expect(empty).toHaveCSS('border-top-width', '0px')
  await expect(empty).toHaveCSS('border-left-width', '0px')
})
