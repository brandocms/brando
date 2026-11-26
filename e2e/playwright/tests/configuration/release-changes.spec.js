import { test, expect } from '../../test-support/setupAuth'
import { syncLV } from '../../utils'

// Block modules → Release changes (brandocms/brando#3612). The
// `release-review` fixture writes a release whose definitions change the
// Example module's template (the Index page uses it), change a module edited
// here since it was applied (a conflict), and differ from one never applied
// from files. Review, Verify, the per-block HTML diff, the side-by-side
// preview, Apply and Revert, driven in Norwegian so the locators name the
// translated labels.
test('reviews, verifies, applies and reverts a release’s module definitions', async ({ page }) => {
  expect((await page.request.post('/e2e/setup_fixtures/release-review')).ok()).toBe(true)
  expect((await page.request.post('/e2e/setup_fixtures/norwegian-admin-user')).ok()).toBe(true)

  // In from Block modules
  await page.goto('/admin/config/content/modules')
  await syncLV(page)
  await page.getByTestId('release-changes-link').click()
  await expect(page).toHaveURL(/\/admin\/config\/content\/modules\/release$/)
  await syncLV(page)

  // The update is ready and checked; the conflict and the never-applied one wait
  const example = page.getByTestId('release-row').filter({ hasText: 'Example module' })
  await expect(example.getByTestId('release-row-check')).toBeChecked()
  await expect(page.getByTestId('release-row').filter({ hasText: 'Kulturslider' }).getByTestId('release-row-check')).toBeDisabled()
  await example.click()
  await syncLV(page)
  await expect(page.getByTestId('release-detail').locator('.admin-text-diff')).toContainText('from-the-release')

  // Verify: a dry run of the entries that use it
  await page.getByTestId('release-tab-entries').click()
  await syncLV(page)
  await page.getByTestId('release-verify-entries').click()
  const entries = page.getByTestId('release-entry')
  await expect(entries.locator('.verify.is-ok')).toHaveCount(await entries.count(), { timeout: 30000 })

  // The per-block HTML diff
  await entries.first().getByRole('button', { name: 'HTML-forskjeller' }).click()
  const diff = page.locator('#release-block-diff')
  await expect(diff).toBeVisible()
  await expect(diff.locator('.text-diff-line.is-ins')).toContainText('from-the-release')
  await diff.locator('.modal-footer').getByRole('button', { name: 'Lukk' }).click()
  await expect(diff).toHaveCount(0)

  // Before and after side by side, the changed block marked in both
  await page.getByTestId('release-tab-preview').click()
  await syncLV(page)
  const after = page.frameLocator('#release-preview-after')
  await expect(after.locator('.brando-proposal-highlight').first()).toBeVisible({ timeout: 30000 })
  await expect(after.locator('article[b-tpl="example"].from-the-release')).toHaveCount(1)
  await expect(page.frameLocator('#release-preview-before').locator('article[b-tpl="example"].from-the-release')).toHaveCount(0)

  // The module's label sits outside the outline, clear of the page's text:
  // the block's own and the block right above it
  const label = after.locator('.brando-proposal-highlight-label')
  await expect(label).toHaveCount(1)
  const afterFrame = await (await page.locator('#release-preview-after').elementHandle()).contentFrame()
  // Polled: the labels are placed again a frame after the layout settles
  const coveredText = () => afterFrame.evaluate(() => {
    const label = document.querySelector('.brando-proposal-highlight-label').getBoundingClientRect()
    const range = document.createRange()
    const lines = [...document.querySelectorAll('article h1, article h2, article .paragraph')].flatMap(text => {
      range.selectNodeContents(text)
      return [...range.getClientRects()].map(line => ({ text: text.textContent.trim(), line }))
    })
    const apart = ({ line }) =>
      label.right <= line.left || line.right <= label.left || label.bottom <= line.top || line.bottom <= label.top
    return { lines: lines.length > 2, covered: lines.filter(line => !apart(line)).map(line => line.text) }
  })
  await expect.poll(coveredText).toEqual({ lines: true, covered: [] })

  await page.getByTestId('release-marks-toggle').click()
  await expect(after.locator('.brando-proposal-highlight')).toHaveCount(0)
  await expect(label).toHaveCount(0)
  await page.getByTestId('release-marks-toggle').click()
  await expect(after.locator('.brando-proposal-highlight').first()).toBeVisible()

  await page.getByTestId('release-full-screen').click()
  await expect(page.locator('#release-preview.release-preview-full')).toBeVisible()
  await page.keyboard.press('Escape')
  await expect(page.locator('#release-preview.release-preview-full')).toHaveCount(0)

  // Apply the one ready change. `toBeVisible()` passes for a dialog left at
  // opacity 0, which takes every click on the screen, so the check is its
  // computed opacity. Escape and the backdrop close it, and it opens again. A
  // click in the dialog's own padding is not the backdrop.
  const confirm = page.locator('#release-confirm')
  await page.getByTestId('release-apply').click()
  await expect(confirm).toHaveCSS('opacity', '1')
  await page.keyboard.press('Escape')
  await expect(confirm).toBeHidden()
  await page.getByTestId('release-apply').click()
  await expect(confirm).toHaveCSS('opacity', '1')
  await page.mouse.click(4, 4)
  await expect(confirm).toBeHidden()
  await page.getByTestId('release-apply').click()
  await expect(confirm).toHaveCSS('opacity', '1')
  await confirm.click({ position: { x: 4, y: 4 } })
  await syncLV(page)
  await expect(confirm).toHaveAttribute('data-dialog-open', 'true')
  await confirm.getByTestId('release-confirm-apply').click()
  await expect(confirm).toBeHidden()
  const banner = page.getByTestId('release-banner')
  await expect(banner).toBeVisible()
  await expect(page.getByTestId('release-applied-row')).toHaveCount(1)
  await expect(example).toHaveCount(0)

  // Revert brings the release's change back to waiting
  await banner.getByRole('button', { name: 'Tilbakestill …' }).click()
  await page.locator('dialog.admin-dialog').getByRole('button', { name: 'Tilbakestill', exact: true }).click()
  await expect(banner).toHaveCount(0)
  await expect(page.getByTestId('release-row').filter({ hasText: 'Example module' })).toHaveCount(1)
})

// A conflict needs a choice; taking the release's version applies it
test('a module changed here and in the release is applied once its version is chosen', async ({ page }) => {
  expect((await page.request.post('/e2e/setup_fixtures/release-review')).ok()).toBe(true)
  expect((await page.request.post('/e2e/setup_fixtures/norwegian-admin-user')).ok()).toBe(true)

  await page.goto('/admin/config/content/modules/release')
  await syncLV(page)

  const conflict = page.getByTestId('release-row').filter({ has: page.locator('.badge--attention', { hasText: 'Konflikt' }) })
  await conflict.click()
  await syncLV(page)
  await expect(page.getByTestId('release-threeway')).toBeVisible()
  await expect(conflict.getByTestId('release-row-check')).toBeDisabled()

  await page.getByTestId('release-choice-release').check()
  await syncLV(page)
  await expect(conflict.getByTestId('release-row-check')).toBeChecked()

  // The update goes out of the apply; the conflict is applied alone
  await page.getByTestId('release-row').filter({ hasText: 'Example module' }).getByTestId('release-row-check').uncheck()
  await page.getByTestId('release-apply').click()
  await page.locator('#release-confirm').getByTestId('release-confirm-apply').click()
  await expect(page.getByTestId('release-banner')).toBeVisible()
  await expect(page.getByTestId('release-applied-row')).toHaveCount(1)
  await expect(page.getByTestId('release-row').filter({ hasText: 'Example module' })).toHaveCount(1)
})

// brandocms/brando#3540: a release that removes a var a block holds a value
// for is ready to apply; the applied module then links to Resolve blocks.
// brandocms/brando#3996: so do the applied banner and, after Keep, the
// notice above the review.
test('a release that removes a var is applied, and the module links to Resolve blocks', async ({ page }) => {
  expect((await page.request.post('/e2e/setup_fixtures/release-removal')).ok()).toBe(true)
  expect((await page.request.post('/e2e/setup_fixtures/norwegian-admin-user')).ok()).toBe(true)

  await page.goto('/admin/config/content/modules/release')
  await syncLV(page)

  const row = page.getByTestId('release-row').filter({ hasText: 'Enkelt bilde med bildetekst' })
  await expect(row.getByTestId('release-row-check')).toBeChecked()
  await row.click()
  await syncLV(page)
  await expect(page.getByTestId('release-removals').locator('li')).toHaveCount(1)

  await page.getByTestId('release-apply').click()
  await page.getByTestId('release-confirm-apply').click()
  await syncLV(page)

  const resolvePath = /\/admin\/config\/content\/modules\/update\/\d+\/stale-blocks$/
  const banner = page.getByTestId('release-banner')
  await expect(banner.getByTestId('release-banner-leftovers')).toBeVisible()
  await expect(banner.getByRole('link', { name: 'Løs blokker' })).toHaveAttribute('href', resolvePath)

  const applied = page.getByTestId('release-applied-row').filter({ hasText: 'Enkelt bilde med bildetekst' })
  await applied.click()
  await syncLV(page)
  await expect(page.getByTestId('release-resolve-blocks')).toHaveAttribute('href', resolvePath)

  // After Keep, the notice above the review still names the blocks
  await banner.getByRole('button', { name: 'Behold' }).click()
  await page.locator('dialog.admin-dialog').getByRole('button', { name: 'Behold', exact: true }).click()
  await expect(banner).toHaveCount(0)
  // The seeds' blocks may hold leftovers too: then it links to the list
  const notice = page.getByTestId('release-leftovers')
  await notice.getByRole('link', { name: 'Løs blokker' }).click()
  await expect(page).toHaveURL(/\/admin\/config\/content\/modules\/(update\/\d+\/)?stale-blocks$/)
})

// brandocms/brando#3996: the apply dialog can drop what blocks hold in the
// removed var, so nothing is left to resolve; Revert puts the value back,
// and the page reads it again.
test('a release apply drops the removed var’s values, and Revert puts them back', async ({ page }) => {
  expect((await page.request.post('/e2e/setup_fixtures/release-drop')).ok()).toBe(true)
  expect((await page.request.post('/e2e/setup_fixtures/norwegian-admin-user')).ok()).toBe(true)
  const bordered = async () => (await (await page.request.get('/release-drop')).text()).includes('data-border="true"')
  expect(await bordered()).toBe(true)

  await page.goto('/admin/config/content/modules/release')
  await syncLV(page)

  // Unticked when the dialog opens; ticked, the apply drops the value
  const confirm = page.locator('#release-confirm')
  await page.getByTestId('release-apply').click()
  await expect(confirm).toHaveCSS('opacity', '1')
  const drop = confirm.getByTestId('release-drop')
  await expect(drop).not.toBeChecked()
  await drop.check()
  await expect(drop).toBeChecked()
  await confirm.getByTestId('release-confirm-apply').click()
  await expect(confirm).toBeHidden()

  const banner = page.getByTestId('release-banner')
  await expect(banner.getByTestId('release-banner-dropped')).toBeVisible()
  await expect(banner.getByRole('button', { name: 'Behold' })).toBeEnabled({ timeout: 30000 })
  // Nothing left to resolve in the applied module
  const applied = page.getByTestId('release-applied-row').filter({ hasText: 'Enkelt bilde med bildetekst' })
  await applied.click()
  await syncLV(page)
  await expect(page.getByTestId('release-resolve-blocks')).toHaveCount(0)
  await expect.poll(bordered, { timeout: 30000 }).toBe(false)

  // Revert puts the value back in the block, and the page reads it again
  await banner.getByRole('button', { name: 'Tilbakestill …' }).click()
  await page.locator('dialog.admin-dialog').getByRole('button', { name: 'Tilbakestill', exact: true }).click()
  await expect(banner).toHaveCount(0)
  await expect.poll(bordered, { timeout: 30000 }).toBe(true)
})

// brandocms/brando#3844: a release that renames a var a block holds a value
// for lists the move, and the apply moves the value: nothing is left to
// resolve, and the page renders the value under the new name.
test('a release that renames a var moves the value in the apply', async ({ page }) => {
  expect((await page.request.post('/e2e/setup_fixtures/release-rename')).ok()).toBe(true)
  expect((await page.request.post('/e2e/setup_fixtures/norwegian-admin-user')).ok()).toBe(true)

  await page.goto('/admin/config/content/modules/release')
  await syncLV(page)

  const row = page.getByTestId('release-row').filter({ hasText: 'Enkelt bilde med bildetekst' })
  await expect(row.getByTestId('release-row-check')).toBeChecked()
  await row.click()
  await syncLV(page)
  await expect(page.getByTestId('release-moves').locator('li')).toContainText('show_border → framed')
  await expect(page.getByTestId('release-removals')).toHaveCount(0)

  await page.getByTestId('release-apply').click()
  await page.getByTestId('release-confirm-apply').click()
  await syncLV(page)

  const applied = page.getByTestId('release-applied-row').filter({ hasText: 'Enkelt bilde med bildetekst' })
  await applied.click()
  await syncLV(page)
  await expect(page.getByTestId('release-resolve-blocks')).toHaveCount(0)

  // The page renders the value under its new name
  await page.goto('/release-rename')
  await expect(page.locator('figure[b-tpl="single-image"]')).toHaveAttribute('data-framed', 'true')
})
