import { test, expect } from '../../test-support/setupAuth'
import { syncLV } from '../../utils'

test.describe('Block Copy/Paste', () => {
  test('copy root module and paste at root level', async ({ page }) => {
    // Navigate to Pages
    await page.goto('/admin')
    await page.getByRole('link', { name: 'Pages & Sections' }).click()
    await syncLV(page)

    // Create new page
    await page.getByRole('link', { name: 'Create page' }).click()
    await syncLV(page)

    // Fill page basics
    await page.getByLabel('Title', { exact: true }).fill('Copy Paste Test Page')
    await page.getByLabel('URI').fill('copy-paste-test')

    // Add a Heading block
    await page.getByRole('button', { name: 'Add block' }).click()
    await page.getByRole('button', { name: 'HEADERS' }).click()
    await page.getByRole('button', { name: 'Heading' }).click()
    await syncLV(page)

    // Verify we have 1 block
    const blocks = page.locator('.entry-block')
    await expect(blocks).toHaveCount(1)

    // Verify no paste buttons exist initially
    await expect(page.locator('.block-paste')).toHaveCount(0)

    // Click the Copy button on the block toolbar
    await page.locator('.block-action.copy').first().click()
    await syncLV(page)

    // After copying, paste buttons should appear at root-compatible positions
    const pasteButtons = page.locator('.block-paste')
    await expect(pasteButtons.first()).toBeVisible()

    // Click the paste button (the one above the first block)
    await pasteButtons.first().click()
    await syncLV(page)

    // Verify we now have 2 blocks
    await expect(blocks).toHaveCount(2)
  })

  test('copy module and paste at bottom of page', async ({ page }) => {
    await page.goto('/admin')
    await page.getByRole('link', { name: 'Pages & Sections' }).click()
    await syncLV(page)

    await page.getByRole('link', { name: 'Create page' }).click()
    await syncLV(page)

    await page.getByLabel('Title', { exact: true }).fill('Copy Paste Bottom Test')
    await page.getByLabel('URI').fill('copy-paste-bottom')

    // Add a Heading block
    await page.getByRole('button', { name: 'Add block' }).click()
    await page.getByRole('button', { name: 'HEADERS' }).click()
    await page.getByRole('button', { name: 'Heading' }).click()
    await syncLV(page)

    // Copy the block
    await page.locator('.block-action.copy').first().click()
    await syncLV(page)

    // Click the bottom paste button (last one on the page, inside blocks-content)
    const bottomPaste = page.locator('.blocks-content > .block-plus-wrapper .block-paste')
    await expect(bottomPaste).toBeVisible()
    await bottomPaste.click()
    await syncLV(page)

    // Verify 2 blocks exist
    await expect(page.locator('.entry-block')).toHaveCount(2)
  })

  test('copy module with vars and verify pasted block has same var values', async ({ page }) => {
    await page.goto('/admin')
    await page.getByRole('link', { name: 'Pages & Sections' }).click()
    await syncLV(page)

    await page.getByRole('link', { name: 'Create page' }).click()
    await syncLV(page)

    await page.getByLabel('Title', { exact: true }).fill('Copy Paste Vars Test')
    await page.getByLabel('URI').fill('copy-paste-vars')

    // Add Single Asset block (has a string var "String label")
    await page.getByRole('button', { name: 'Add block' }).click()
    await page.getByRole('button', { name: 'MEDIA' }).click()
    await page.getByRole('button', { name: 'Single Asset' }).click()
    await syncLV(page)

    // Edit the var value
    const firstBlock = page.locator('.entry-block').first()
    const varInput = firstBlock.locator('.block-vars').getByLabel('String label')
    await varInput.fill('Custom Value For Copy')
    await page.waitForTimeout(400) // debounce
    await syncLV(page)

    // Copy the block
    await firstBlock.locator('.block-action.copy').click()
    await syncLV(page)

    // Paste at the bottom
    const bottomPaste = page.locator('.blocks-content > .block-plus-wrapper .block-paste')
    await bottomPaste.click()
    await syncLV(page)

    // Verify 2 blocks
    await expect(page.locator('.entry-block')).toHaveCount(2)

    // Verify the second block has the same var value
    const secondBlock = page.locator('.entry-block').nth(1)
    const pastedVarInput = secondBlock.locator('.block-vars').getByLabel('String label')
    await expect(pastedVarInput).toHaveValue('Custom Value For Copy')

    // Modify the pasted block's var to verify independence
    await pastedVarInput.fill('Modified Pasted Value')
    await page.waitForTimeout(400)
    await syncLV(page)

    // Original should be unchanged
    await expect(varInput).toHaveValue('Custom Value For Copy')
  })

  test('copy module and paste inside container', async ({ page }) => {
    await page.goto('/admin')
    await page.getByRole('link', { name: 'Pages & Sections' }).click()
    await syncLV(page)

    await page.getByRole('link', { name: 'Create page' }).click()
    await syncLV(page)

    await page.getByLabel('Title', { exact: true }).fill('Copy Paste Container Test')
    await page.getByLabel('URI').fill('copy-paste-container')

    // First add a container block
    await page.getByRole('button', { name: 'Add block' }).click()
    await page.getByRole('button', { name: 'Container' }).click()
    await syncLV(page)

    // Add a module inside the container
    const container = page.locator('[data-block-type="container"]')
    await container.locator('.block-plus').first().click()
    await page.getByRole('button', { name: 'HEADERS' }).click()
    await page.getByRole('button', { name: 'Heading' }).click()
    await syncLV(page)

    // Verify 1 child block inside container
    const containerChildren = container.locator('.block-children > [data-uid]')
    await expect(containerChildren).toHaveCount(1)

    // Copy the child module block (target the child specifically, not the container itself)
    const childBlock = container.locator('.block-children > [data-uid]').first()
    await childBlock.locator('.block-action.copy').click()
    await syncLV(page)

    // A paste button should appear inside the container (at the bottom of children)
    // The module type can paste at :container context
    const containerPaste = container.locator('.block-plus-wrapper .block-paste')
    await expect(containerPaste.first()).toBeVisible()
    await containerPaste.first().click()
    await syncLV(page)

    // Verify 2 children now in container
    await expect(container.locator('.block-children > [data-uid]')).toHaveCount(2)
  })

  test('copy root module and paste persists after save', async ({ page }) => {
    await page.goto('/admin')
    await page.getByRole('link', { name: 'Pages & Sections' }).click()
    await syncLV(page)

    await page.getByRole('link', { name: 'Create page' }).click()
    await syncLV(page)

    await page.getByLabel('Title', { exact: true }).fill('Copy Paste Persist Test')
    await page.getByLabel('URI').fill('copy-paste-persist')

    // Add a Heading block
    await page.getByRole('button', { name: 'Add block' }).click()
    await page.getByRole('button', { name: 'HEADERS' }).click()
    await page.getByRole('button', { name: 'Heading' }).click()
    await syncLV(page)

    // Copy and paste to get 2 blocks
    await page.locator('.block-action.copy').first().click()
    await syncLV(page)

    const bottomPaste = page.locator('.blocks-content > .block-plus-wrapper .block-paste')
    await bottomPaste.click()
    await syncLV(page)

    await expect(page.locator('.entry-block')).toHaveCount(2)

    // Save
    await page.getByTestId('submit').click()
    await expect(page).toHaveURL(/\/admin\/pages$/)
    await syncLV(page)

    // Re-open the page
    await page.getByRole('link', { name: 'Copy Paste Persist Test' }).click()
    await syncLV(page)

    // Verify 2 blocks persisted
    await expect(page.locator('.entry-block')).toHaveCount(2)
  })

  test('smart matching: module_entry only pastes into matching multi-block', async ({ page }) => {
    await page.goto('/admin')
    await page.getByRole('link', { name: 'Pages & Sections' }).click()
    await syncLV(page)

    await page.getByRole('link', { name: 'Create page' }).click()
    await syncLV(page)

    await page.getByLabel('Title', { exact: true }).fill('Smart Match Test')
    await page.getByLabel('URI').fill('smart-match-test')

    // Add a Team Section (multi block)
    await page.getByRole('button', { name: 'Add block' }).click()
    await page.getByRole('button', { name: 'COPY PASTE TEST' }).click()
    await page.getByRole('button', { name: 'Team Section' }).click()
    await syncLV(page)

    // The multi block should have an add button for entries
    const multiBlock = page.locator('[data-module-multi="true"]')
    await expect(multiBlock).toBeVisible()

    // Add a team member entry
    await multiBlock.locator('.block-plus').last().click()
    await page.getByRole('button', { name: 'COPY PASTE TEST' }).click()
    await page.getByRole('button', { name: 'Team Member' }).click()
    await syncLV(page)

    // Edit the team member vars
    const memberBlock = multiBlock.locator('.block-children [data-uid]').first()
    await memberBlock.locator('.block-vars').getByLabel('Name').fill('Alice Smith')
    await page.waitForTimeout(400)
    await syncLV(page)
    await memberBlock.locator('.block-vars').getByLabel('Role').fill('Lead Engineer')
    await page.waitForTimeout(400)
    await syncLV(page)

    // Copy the team member entry
    await memberBlock.locator('.block-action.copy').click()
    await syncLV(page)

    // Paste button should appear inside the multi-block (matching parent_module_id)
    const multiPaste = multiBlock.locator('.block-plus-wrapper .block-paste')
    await expect(multiPaste.first()).toBeVisible()

    // Paste the entry
    await multiPaste.first().click()
    await syncLV(page)

    // Verify 2 entries in the multi block
    await expect(multiBlock.locator('.block-children [data-uid]')).toHaveCount(2)

    // Verify the pasted entry has the same var values
    const pastedMember = multiBlock.locator('.block-children [data-uid]').nth(1)
    await expect(pastedMember.locator('.block-vars').getByLabel('Name')).toHaveValue('Alice Smith')
    await expect(pastedMember.locator('.block-vars').getByLabel('Role')).toHaveValue(
      'Lead Engineer'
    )
  })
})
