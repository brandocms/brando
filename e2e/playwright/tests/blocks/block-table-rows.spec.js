import { test, expect } from '../../test-support/setupAuth'
import { syncLV } from '../../utils'

test.describe('Block Table Rows', () => {
  test('add, edit, reorder, delete table rows and verify persistence', async ({ page }) => {
    // Navigate to Pages
    await page.goto('/admin')
    await page.getByRole('link', { name: 'Pages & Sections' }).click()
    await syncLV(page)

    // Create new page
    await page.getByRole('link', { name: 'Create page' }).click()
    await syncLV(page)

    // Fill page basics
    await page.getByLabel('Title', { exact: true }).fill('Table Rows Test Page')
    await page.getByLabel('URI').fill('table-rows-test')

    // Add block with table template
    await page.getByRole('button', { name: 'Add block' }).click()
    await page.getByRole('button', { name: 'TABLES' }).click()
    await page.getByRole('button', { name: 'Person List' }).click()
    await syncLV(page)

    // Verify empty state message is shown
    await expect(page.locator('.block-instructions')).toBeVisible()

    // === TEST 1: Add first table row ===
    await page.getByTestId('add-table-row').evaluate(btn => btn.click())
    await syncLV(page)

    // Verify row was added
    const tableRows = page.locator('.table-rows .table-row')
    await expect(tableRows).toHaveCount(1)

    // Fill in first row data
    await tableRows.nth(0).getByRole('textbox', { name: 'Name' }).fill('Alice')
    await tableRows.nth(0).getByRole('textbox', { name: 'Role' }).fill('Developer')
    await syncLV(page)

    // === TEST 2: Add second table row ===
    await page.getByTestId('add-table-row').evaluate(btn => btn.click())
    await syncLV(page)

    await expect(tableRows).toHaveCount(2)

    // Fill in second row data
    await tableRows.nth(1).getByRole('textbox', { name: 'Name' }).fill('Bob')
    await tableRows.nth(1).getByRole('textbox', { name: 'Role' }).fill('Designer')
    await syncLV(page)

    // === TEST 3: Add third table row ===
    await page.getByTestId('add-table-row').evaluate(btn => btn.click())
    await syncLV(page)

    await expect(tableRows).toHaveCount(3)

    // Fill in third row data
    await tableRows.nth(2).getByRole('textbox', { name: 'Name' }).fill('Charlie')
    await tableRows.nth(2).getByRole('textbox', { name: 'Role' }).fill('Manager')
    await syncLV(page)

    // Verify all data is correct before saving
    await expect(tableRows.nth(0).getByRole('textbox', { name: 'Name' })).toHaveValue('Alice')
    await expect(tableRows.nth(0).getByRole('textbox', { name: 'Role' })).toHaveValue('Developer')
    await expect(tableRows.nth(1).getByRole('textbox', { name: 'Name' })).toHaveValue('Bob')
    await expect(tableRows.nth(1).getByRole('textbox', { name: 'Role' })).toHaveValue('Designer')
    await expect(tableRows.nth(2).getByRole('textbox', { name: 'Name' })).toHaveValue('Charlie')
    await expect(tableRows.nth(2).getByRole('textbox', { name: 'Role' })).toHaveValue('Manager')

    // === TEST 4: Save and verify persistence ===
    await page.getByTestId('submit').click()
    await expect(page).toHaveURL(/\/admin\/pages$/)
    await syncLV(page)

    // Re-open the page
    await page.getByRole('link', { name: 'Table Rows Test Page' }).click()
    await syncLV(page)

    // Verify rows persisted with correct data and order
    const persistedRows = page.locator('.table-rows .table-row')
    await expect(persistedRows).toHaveCount(3)
    await expect(persistedRows.nth(0).getByRole('textbox', { name: 'Name' })).toHaveValue('Alice')
    await expect(persistedRows.nth(0).getByRole('textbox', { name: 'Role' })).toHaveValue(
      'Developer'
    )
    await expect(persistedRows.nth(1).getByRole('textbox', { name: 'Name' })).toHaveValue('Bob')
    await expect(persistedRows.nth(1).getByRole('textbox', { name: 'Role' })).toHaveValue(
      'Designer'
    )
    await expect(persistedRows.nth(2).getByRole('textbox', { name: 'Name' })).toHaveValue(
      'Charlie'
    )
    await expect(persistedRows.nth(2).getByRole('textbox', { name: 'Role' })).toHaveValue(
      'Manager'
    )

    // === TEST 5: Reorder rows (drag Charlie to first position) ===
    const charlieRow = persistedRows.nth(2)
    const aliceRow = persistedRows.nth(0)

    // Scroll into view
    await charlieRow.scrollIntoViewIfNeeded()
    await aliceRow.scrollIntoViewIfNeeded()

    // Get bounding boxes
    const sourceBox = await charlieRow.locator('.sort-handle').boundingBox()
    const targetBox = await aliceRow.locator('.sort-handle').boundingBox()

    if (sourceBox && targetBox) {
      const sourceX = sourceBox.x + sourceBox.width / 2
      const sourceY = sourceBox.y + sourceBox.height / 2
      const targetX = targetBox.x + targetBox.width / 2
      const targetY = targetBox.y + targetBox.height / 2

      await page.mouse.move(sourceX, sourceY)
      await page.mouse.down()
      await page.waitForTimeout(100)
      await page.mouse.move(targetX, targetY, { steps: 20 })
      await page.waitForTimeout(100)
      await page.mouse.up()
    }

    await syncLV(page)

    // Verify new order: Charlie, Alice, Bob
    const reorderedRows = page.locator('.table-rows .table-row')
    await expect(reorderedRows.nth(0).getByRole('textbox', { name: 'Name' })).toHaveValue(
      'Charlie'
    )
    await expect(reorderedRows.nth(1).getByRole('textbox', { name: 'Name' })).toHaveValue('Alice')
    await expect(reorderedRows.nth(2).getByRole('textbox', { name: 'Name' })).toHaveValue('Bob')

    // Save and verify reorder persisted
    await page.getByTestId('submit').click()
    await syncLV(page)

    await page.getByRole('link', { name: 'Table Rows Test Page' }).click()
    await syncLV(page)

    const reorderedPersistedRows = page.locator('.table-rows .table-row')
    await expect(
      reorderedPersistedRows.nth(0).getByRole('textbox', { name: 'Name' })
    ).toHaveValue('Charlie')
    await expect(
      reorderedPersistedRows.nth(0).getByRole('textbox', { name: 'Role' })
    ).toHaveValue('Manager')
    await expect(
      reorderedPersistedRows.nth(1).getByRole('textbox', { name: 'Name' })
    ).toHaveValue('Alice')
    await expect(
      reorderedPersistedRows.nth(1).getByRole('textbox', { name: 'Role' })
    ).toHaveValue('Developer')
    await expect(
      reorderedPersistedRows.nth(2).getByRole('textbox', { name: 'Name' })
    ).toHaveValue('Bob')
    await expect(
      reorderedPersistedRows.nth(2).getByRole('textbox', { name: 'Role' })
    ).toHaveValue('Designer')

    // === TEST 6: Edit two rows ===
    await reorderedPersistedRows
      .nth(1)
      .getByRole('textbox', { name: 'Role' })
      .fill('Senior Developer')
    // Wait for debounce (350ms) + buffer before syncLV
    await page.waitForTimeout(400)
    await syncLV(page)
    await reorderedPersistedRows
      .nth(2)
      .getByRole('textbox', { name: 'Role' })
      .fill('Senior Designer')
    // Wait for debounce (350ms) + buffer before syncLV
    await page.waitForTimeout(400)
    await syncLV(page)

    // Save and verify edit persisted
    await page.getByTestId('submit').click()
    await syncLV(page)

    await page.getByRole('link', { name: 'Table Rows Test Page' }).click()
    await syncLV(page)

    await expect(
      page.locator('.table-rows .table-row').nth(1).getByRole('textbox', { name: 'Role' })
    ).toHaveValue('Senior Developer')
    await expect(
      page.locator('.table-rows .table-row').nth(2).getByRole('textbox', { name: 'Role' })
    ).toHaveValue('Senior Designer')

    // === TEST 7: Delete a row (delete Alice) ===
    // Delete button is hidden, use evaluate to trigger native click
    await page
      .locator('.table-rows .table-row')
      .nth(1)
      .locator('button.delete-image')
      .evaluate(btn => btn.click())
    await syncLV(page)

    // Verify only 2 rows remain
    await expect(page.locator('.table-rows .table-row')).toHaveCount(2)
    await expect(
      page.locator('.table-rows .table-row').nth(0).getByRole('textbox', { name: 'Name' })
    ).toHaveValue('Charlie')
    await expect(
      page.locator('.table-rows .table-row').nth(1).getByRole('textbox', { name: 'Name' })
    ).toHaveValue('Bob')

    // Save and verify deletion persisted
    await page.getByTestId('submit').click()
    await syncLV(page)

    await page.getByRole('link', { name: 'Table Rows Test Page' }).click()
    await syncLV(page)

    await expect(page.locator('.table-rows .table-row')).toHaveCount(2)
    await expect(
      page.locator('.table-rows .table-row').nth(0).getByRole('textbox', { name: 'Name' })
    ).toHaveValue('Charlie')
    await expect(
      page.locator('.table-rows .table-row').nth(0).getByRole('textbox', { name: 'Role' })
    ).toHaveValue('Manager')
    await expect(
      page.locator('.table-rows .table-row').nth(1).getByRole('textbox', { name: 'Name' })
    ).toHaveValue('Bob')
    await expect(
      page.locator('.table-rows .table-row').nth(1).getByRole('textbox', { name: 'Role' })
    ).toHaveValue('Senior Designer')
  })

  test('adding row after deletion maintains correct sequence', async ({ page }) => {
    await page.goto('/admin')
    await page.getByRole('link', { name: 'Pages & Sections' }).click()
    await syncLV(page)

    await page.getByRole('link', { name: 'Create page' }).click()
    await syncLV(page)

    await page.getByLabel('Title', { exact: true }).fill('Sequence Test Page')
    await page.getByLabel('URI').fill('sequence-test')

    // Add block with table template
    await page.getByRole('button', { name: 'Add block' }).click()
    await page.getByRole('button', { name: 'TABLES' }).click()
    await page.getByRole('button', { name: 'Person List' }).click()
    await syncLV(page)

    // Add two rows
    await page.getByTestId('add-table-row').evaluate(btn => btn.click())
    await syncLV(page)
    await page
      .locator('.table-rows .table-row')
      .nth(0)
      .getByRole('textbox', { name: 'Name' })
      .fill('First')
    await syncLV(page)

    await page.getByTestId('add-table-row').evaluate(btn => btn.click())
    await syncLV(page)
    await page
      .locator('.table-rows .table-row')
      .nth(1)
      .getByRole('textbox', { name: 'Name' })
      .fill('Second')
    await syncLV(page)

    // Save
    await page.getByTestId('submit').click()
    await expect(page).toHaveURL(/\/admin\/pages$/)
    await syncLV(page)

    // Re-open
    await page.getByRole('link', { name: 'Sequence Test Page' }).click()
    await syncLV(page)

    // Delete first row - need to use evaluate to properly trigger the button click
    // which sets its value in the form data and dispatches change event
    await page
      .locator('.table-rows .table-row')
      .nth(0)
      .locator('button.delete-image')
      .evaluate(btn => {
        btn.click()
      })
    await syncLV(page)

    // Verify only 1 row remains after delete
    await expect(page.locator('.table-rows .table-row')).toHaveCount(1)
    await expect(
      page.locator('.table-rows .table-row').nth(0).getByRole('textbox', { name: 'Name' })
    ).toHaveValue('Second')

    // Add a new row (should become row index 1)
    await page.getByTestId('add-table-row').evaluate(btn => btn.click())
    await syncLV(page)

    // Verify we now have 2 rows
    await expect(page.locator('.table-rows .table-row')).toHaveCount(2)
    await page
      .locator('.table-rows .table-row')
      .nth(1)
      .getByRole('textbox', { name: 'Name' })
      .fill('Third')
    await syncLV(page)

    // Save and verify
    await page.getByTestId('submit').click()
    await syncLV(page)

    await page.getByRole('link', { name: 'Sequence Test Page' }).click()
    await syncLV(page)

    // Verify order: Second, Third (First was deleted)
    const rows = page.locator('.table-rows .table-row')
    await expect(rows).toHaveCount(2)
    await expect(rows.nth(0).getByRole('textbox', { name: 'Name' })).toHaveValue('Second')
    await expect(rows.nth(1).getByRole('textbox', { name: 'Name' })).toHaveValue('Third')
  })
})
