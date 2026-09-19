import { test, expect } from '../../test-support/setupAuth'
import { syncLV, dragAndDrop } from '../../utils'

test.describe('Block Identifier Selection', () => {
  test('add, reorder, remove, re-add identifiers and verify persistence', async ({ page }) => {
    // Navigate to Pages
    await page.goto('/admin')
    await page.getByRole('link', { name: 'Pages & Sections' }).click()
    await syncLV(page)

    // Create new page
    await page.getByRole('link', { name: 'Create page' }).click()
    await syncLV(page)

    // Fill page basics
    await page.getByLabel('Title', { exact: true }).fill('Identifier Test Page')
    await page.getByLabel('URI').fill('identifier-test')

    // Add datasource block
    await page.getByRole('button', { name: 'Add block' }).click()
    await page.getByRole('button', { name: 'DATASOURCE' }).click()
    await page.getByRole('button', { name: 'Featured Projects' }).click()
    await syncLV(page)

    // Click "Select entries" button to open modal
    await page.getByRole('button', { name: 'Select entries' }).click()
    await syncLV(page)

    // Verify modal is open and identifiers are visible
    await expect(page.locator('.identifier').first()).toBeVisible()

    // === TEST 1: Add identifiers ===
    // Select Alpha first
    await page.locator('.identifier').filter({ hasText: 'Test Project Alpha' }).click()
    await syncLV(page)

    // Select Beta second
    await page.locator('.identifier').filter({ hasText: 'Test Project Beta' }).click()
    await syncLV(page)

    // Select Gamma third
    await page.locator('.identifier').filter({ hasText: 'Test Project Gamma' }).click()
    await syncLV(page)

    // Close modal by clicking the X button
    await page.locator('[id^="select-entries-"] .modal-close').click()
    await syncLV(page)

    // Verify 3 identifiers in selected list (use specific selector to avoid matching modal content)
    const selectedEntries = page.locator(
      '.module-datasource-selected .selected-entries .identifier'
    )
    await expect(selectedEntries).toHaveCount(3)

    // Verify order: Alpha, Beta, Gamma
    await expect(selectedEntries.nth(0)).toContainText('Alpha')
    await expect(selectedEntries.nth(1)).toContainText('Beta')
    await expect(selectedEntries.nth(2)).toContainText('Gamma')

    // === TEST 2: Save and reload to verify persistence ===
    await page.getByTestId('submit').click()
    // Wait for redirect to pages list before syncing new page
    await expect(page).toHaveURL(/\/admin\/pages$/)
    await syncLV(page)

    // Re-open the page
    await page.getByRole('link', { name: 'Identifier Test Page' }).click()
    await syncLV(page)

    // Verify identifiers persisted
    const persistedEntries = page.locator(
      '.module-datasource-selected .selected-entries .identifier'
    )
    await expect(persistedEntries).toHaveCount(3)
    await expect(persistedEntries.nth(0)).toContainText('Alpha')
    await expect(persistedEntries.nth(1)).toContainText('Beta')
    await expect(persistedEntries.nth(2)).toContainText('Gamma')

    // === TEST 3: Reorder identifiers (drag Gamma to first position) ===
    const gammaIdentifier = page
      .locator('.module-datasource-selected .selected-entries .identifier')
      .filter({ hasText: 'Gamma' })
    const alphaIdentifier = page
      .locator('.module-datasource-selected .selected-entries .identifier')
      .filter({ hasText: 'Alpha' })

    // 1. Ensure elements are stable and in view
    await gammaIdentifier.scrollIntoViewIfNeeded()
    await alphaIdentifier.scrollIntoViewIfNeeded()

    // 2. Get Bounding Boxes (coordinates)
    const sourceBox = await gammaIdentifier.boundingBox()
    const targetBox = await alphaIdentifier.boundingBox()

    if (sourceBox && targetBox) {
      // Calculate center points
      const sourceX = sourceBox.x + sourceBox.width / 2
      const sourceY = sourceBox.y + sourceBox.height / 2
      const targetX = targetBox.x + targetBox.width / 2
      const targetY = targetBox.y + targetBox.height / 2

      // 3. Perform the Drag
      // Move to source
      await page.mouse.move(sourceX, sourceY)
      await page.mouse.down()

      // Optional: Small pause to let SortableJS catch the 'down' event
      await page.waitForTimeout(100)

      // MOVE with steps (The Secret Sauce)
      // 'steps: 20' breaks the movement into 20 small chunks, triggering the drag-over detection
      await page.mouse.move(targetX, targetY, { steps: 20 })

      // Optional: Wait for the swap animation to settle before releasing
      await page.waitForTimeout(100)
      await page.mouse.up()
    }

    // 4. Sync and Verify
    await syncLV(page) // Your custom sync function

    // Verify new order
    const reorderedEntries = page.locator(
      '.module-datasource-selected .selected-entries .identifier'
    )
    await expect(reorderedEntries.nth(0)).toContainText('Gamma')
    await expect(reorderedEntries.nth(1)).toContainText('Alpha')
    await expect(reorderedEntries.nth(2)).toContainText('Beta')

    // === TEST 4: Remove identifier (remove Alpha) ===
    await page
      .locator('.module-datasource-selected .selected-entries .identifier')
      .filter({ hasText: 'Alpha' })
      .locator('button[name*="drop_block_identifier_ids"]')
      .click()
    await syncLV(page)

    // Verify only 2 entries remain
    await expect(
      page.locator('.module-datasource-selected .selected-entries .identifier')
    ).toHaveCount(2)
    await expect(
      page.locator('.module-datasource-selected .selected-entries .identifier').nth(0)
    ).toContainText('Gamma')
    await expect(
      page.locator('.module-datasource-selected .selected-entries .identifier').nth(1)
    ).toContainText('Beta')

    // Save and verify removal persisted
    await page.getByTestId('submit').click()
    await syncLV(page)

    await page.getByRole('link', { name: 'Identifier Test Page' }).click()
    await syncLV(page)

    await expect(
      page.locator('.module-datasource-selected .selected-entries .identifier')
    ).toHaveCount(2)

    // === TEST 5: Re-add removed identifier (re-add Alpha) ===
    await page.getByRole('button', { name: 'Select entries' }).click()
    await syncLV(page)

    await page.locator('.identifier').filter({ hasText: 'Test Project Alpha' }).click()
    await syncLV(page)

    // Close modal by clicking the X button
    await page.locator('[id^="select-entries-"] .modal-close').click()
    // Wait for the select-entries modal to fully close (has 300-400ms animation)
    await expect(page.locator('.modal[id^="select-entries-"]')).not.toBeVisible({ timeout: 5000 })
    await syncLV(page)

    // Verify 3 entries again (Alpha should be at the end)
    await expect(
      page.locator('.module-datasource-selected .selected-entries .identifier')
    ).toHaveCount(3)
    await expect(
      page.locator('.module-datasource-selected .selected-entries .identifier').nth(2)
    ).toContainText('Alpha')

    // Save and verify re-add persisted
    await page.getByTestId('submit').click()
    await syncLV(page)

    await page.getByRole('link', { name: 'Identifier Test Page' }).click()
    await syncLV(page)

    await expect(
      page.locator('.module-datasource-selected .selected-entries .identifier')
    ).toHaveCount(3)
    await expect(
      page.locator('.module-datasource-selected .selected-entries .identifier').nth(0)
    ).toContainText('Gamma')
    await expect(
      page.locator('.module-datasource-selected .selected-entries .identifier').nth(1)
    ).toContainText('Beta')
    await expect(
      page.locator('.module-datasource-selected .selected-entries .identifier').nth(2)
    ).toContainText('Alpha')
  })

  test('clicking same identifier twice toggles selection', async ({ page }) => {
    await page.goto('/admin')
    await page.getByRole('link', { name: 'Pages & Sections' }).click()
    await syncLV(page)

    await page.getByRole('link', { name: 'Create page' }).click()
    await syncLV(page)

    await page.getByLabel('Title', { exact: true }).fill('Toggle Test Page')
    await page.getByLabel('URI').fill('toggle-test')

    // Add datasource block
    await page.getByRole('button', { name: 'Add block' }).click()
    await page.getByRole('button', { name: 'DATASOURCE' }).click()
    await page.getByRole('button', { name: 'Featured Projects' }).click()
    await syncLV(page)

    await page.getByRole('button', { name: 'Select entries' }).click()
    await syncLV(page)

    // Click Alpha to select (use modal-scoped selector)
    await page
      .locator('[id^="select-entries-"] .identifier')
      .filter({ hasText: 'Test Project Alpha' })
      .click()
    await syncLV(page)

    // Verify selected
    await expect(
      page.locator('.module-datasource-selected .selected-entries .identifier')
    ).toHaveCount(1)

    // Click Alpha again to deselect (use modal-scoped selector)
    await page
      .locator('[id^="select-entries-"] .identifier')
      .filter({ hasText: 'Test Project Alpha' })
      .click()
    await syncLV(page)

    // Verify deselected
    await expect(
      page.locator('.module-datasource-selected .selected-entries .identifier')
    ).toHaveCount(0)

    // Close modal by clicking the X button
    await page.locator('[id^="select-entries-"] .modal-close').click()
  })
})
