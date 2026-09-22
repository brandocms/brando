import { test, expect } from '../../test-support/setupAuth'
import { syncLV } from '../../utils'

// Structural locators only: labels are translated and must not be pinned.
test('the content SEO tab audits published pages', async ({ page }, testInfo) => {
  await page.setViewportSize({ width: 1440, height: 1000 })
  await page.goto('/admin/config/seo')
  await syncLV(page)

  const tabs = page.locator('nav.seo-tabs')
  await expect(tabs.locator('button[phx-value-tab="settings"]')).toHaveAttribute('aria-current', 'page')
  await expect(page.locator('textarea[name="seo[robots]"]')).toBeVisible()

  await tabs.locator('button[phx-value-tab="content"]').click()
  await expect(page).toHaveURL('/admin/config/seo?tab=content')
  await syncLV(page)

  const audit = page.locator('.seo-audit')
  await expect(audit.locator('.seo-stats')).toBeVisible({ timeout: 15000 })
  await expect(audit.locator('.seo-audit-table tbody tr.seo-audit-row').first()).toBeVisible()
  await expect(tabs.locator('button[phx-value-tab="content"] .seo-score-badge')).toBeVisible()

  const firstToggle = audit.locator('.seo-row-toggle').first()
  await firstToggle.click()
  await expect(firstToggle).toHaveAttribute('aria-expanded', 'true')
  await expect(audit.locator('.seo-audit-details .seo-check-table tbody tr').first()).toBeVisible()
  await expect(audit.locator('.seo-audit-details .seo-search-preview')).toBeVisible()

  await page.screenshot({ path: testInfo.outputPath('seo-content-desktop.png'), fullPage: true, animations: 'disabled' })

  // The AI controls only render when a provider is configured, which a plain
  // e2e run is not. Exercise them when they are there rather than pinning the
  // run to a key.
  const picker = audit.locator('.seo-context-picker')

  if (await picker.count()) {
    await expect(audit.locator('.seo-audit-details button[phx-click="generate_description"]')).toBeVisible()

    await picker.locator('.seo-context-summary').click()
    await syncLV(page)
    const chip = picker.locator('.seo-chip').first()
    const pressed = await chip.getAttribute('aria-pressed')
    await chip.click()
    await syncLV(page)
    await expect(chip).toHaveAttribute('aria-pressed', pressed === 'true' ? 'false' : 'true')
    // Picking a field must not collapse the panel it was picked in.
    await expect(picker.locator('.seo-context-summary')).toHaveAttribute('aria-expanded', 'true')

    await page.screenshot({
      path: testInfo.outputPath('seo-content-ai-context.png'),
      fullPage: true,
      animations: 'disabled'
    })

    await chip.click()
    await syncLV(page)
  }

  // Drafts toggle re-runs the audit; the table stays populated.
  const drafts = audit.locator('.seo-chip-toggle')
  await drafts.click()
  await syncLV(page)
  await expect(drafts).toHaveAttribute('aria-pressed', 'true')
  await expect(audit.locator('.seo-stats')).toBeVisible({ timeout: 15000 })

  await page.setViewportSize({ width: 390, height: 844 })
  await expect.poll(() => page.evaluate(() => document.documentElement.scrollWidth)).toBeLessThanOrEqual(390)
  await page.screenshot({ path: testInfo.outputPath('seo-content-mobile.png'), fullPage: true, animations: 'disabled' })

  // The settings tab still holds the form after switching back.
  await page.setViewportSize({ width: 1440, height: 1000 })
  await tabs.locator('button[phx-value-tab="settings"]').click()
  await expect(page).toHaveURL('/admin/config/seo?tab=settings')
  await expect(page.locator('textarea[name="seo[robots]"]')).toBeVisible()
})
