import { test, expect } from '../../test-support/setupAuth'
import { syncLV } from '../../utils'

// The link var's identifier picker filters client-side: the Brando.SelectFilter
// hook toggles `.filter-hidden` on each `.identifier`, so that class has to
// actually hide them. It did not while the rule lived nested under the
// multiselect options, which left the filter input inert.
test.describe('Link var identifier picker', () => {
  test('filtering hides non-matching identifiers', async ({ page }) => {
    await page.goto('/admin')
    await page.getByText('Configuration').click()
    await page.getByRole('link', { name: 'Navigation' }).click()
    await page.getByRole('link', { name: 'Main menu →' }).click()
    await syncLV(page)

    // Open the first menu item's link modal
    await page.locator('#menu_items_0_link_0_identifier_id-field-base').click()
    await syncLV(page)

    const modal = page.locator('#var-menu_items_0_link_0-link-config')
    await expect(modal).toBeVisible()

    // Switch the link type to Identifier
    await modal.locator('#menu_items_0_link_0_link_type-field-base').getByText('Identifier').click()
    await syncLV(page)

    // Projects (labelled "Cases" here) is the only seeded identifier schema
    const schemaButton = modal.locator('.button-group-vertical.tiny button', { hasText: 'Cases' })
    await schemaButton.click()
    await syncLV(page)

    // The picked schema button reflects the selection
    await expect(schemaButton).toHaveClass(/selected/)

    const identifiers = modal.locator('.identifier-options .identifier')
    await expect(identifiers.first()).toBeVisible()
    const total = await identifiers.count()
    expect(total).toBe(3)

    const filterInput = modal.locator('.select-filter input.text')

    // A term unique to one entry leaves only that entry visible
    await filterInput.fill('alpha')
    await expect(identifiers.filter({ visible: true })).toHaveCount(1)
    await expect(identifiers.filter({ visible: true })).toHaveAttribute(
      'data-label',
      'Test Project Alpha'
    )

    // A term matching nothing hides every row and shows the empty state
    await filterInput.fill('zzz-no-such-identifier-zzz')
    await expect(identifiers.filter({ visible: true })).toHaveCount(0)
    await expect(modal.locator('.identifier-options .no-results')).toBeVisible()

    // Clearing restores the full list
    await modal.locator('.select-filter .filter-clear').click()
    await expect(identifiers.filter({ visible: true })).toHaveCount(total)
    await expect(modal.locator('.identifier-options .no-results')).not.toBeVisible()
  })
})
