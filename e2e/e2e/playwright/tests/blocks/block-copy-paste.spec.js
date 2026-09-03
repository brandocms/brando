import { test, expect } from '../../test-support/setupAuth'
import { syncLV } from '../../utils'

/**
 * Opens the block action dropdown and clicks the Copy button.
 * @param {import('@playwright/test').Locator} scope - A locator scoped to the block element
 */
async function copyBlock(scope) {
  await scope.locator('.block-action-dropdown > .block-action').click()
  await scope.locator('.block-action-dropdown-content button', { hasText: 'Copy' }).click()
}

/**
 * Creates a page with the given title/uri and saves it, landing back on the
 * page list.
 */
async function createPage(page, title, uri) {
  await page.goto('/admin/pages')
  await syncLV(page)
  await page.getByRole('link', { name: 'Create page' }).click()
  await syncLV(page)
  await page.getByLabel('Title', { exact: true }).fill(title)
  await page.getByLabel('URI').fill(uri)
}

async function savePage(page) {
  await page.getByTestId('submit').click()
  await expect(page).toHaveURL(/\/admin\/pages$/)
  await syncLV(page)
}

async function openPage(page, title) {
  await page.goto('/admin/pages')
  await syncLV(page)
  await page.getByRole('link', { name: title }).click()
  await syncLV(page)
}

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

    // No paste target is offered before anything is copied. Root and container
    // paste buttons are always in the DOM and shown by CSS from the block
    // field's `data-paste-allow` — threading `clipboard_meta` to every block
    // instead cost 849 KB per copy at 115 blocks — so this asserts on
    // visibility, which is the property the user actually sees.
    await expect(page.locator('.block-paste').first()).toBeHidden()

    // Click the Copy button via the block toolbar dropdown
    await copyBlock(page.locator('.entry-block').first())
    await syncLV(page)

    // After copying, paste buttons should appear at root-compatible positions
    const pasteButtons = page.locator('.block-paste:visible')
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

    // Copy the block via dropdown
    await copyBlock(page.locator('.entry-block').first())
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

    // Copy the block via dropdown
    await copyBlock(firstBlock)
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
    await copyBlock(childBlock)
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
    await copyBlock(page.locator('.entry-block').first())
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
    await page.getByRole('button', { name: /^Team Member\b/ }).click()
    await syncLV(page)

    // Edit the team member vars
    const memberBlock = multiBlock.locator('.block-children [data-uid]').first()
    await memberBlock.locator('.block-vars').getByLabel('Name').fill('Alice Smith')
    await page.waitForTimeout(400)
    await syncLV(page)
    await memberBlock.locator('.block-vars').getByLabel('Role').fill('Lead Engineer')
    await page.waitForTimeout(400)
    await syncLV(page)

    // Copy the team member entry via dropdown
    await copyBlock(memberBlock)
    await syncLV(page)

    // Paste button should appear inside the multi-block (matching parent_module_id).
    // Scoped by `data-paste-ctx` because the multi block also carries a
    // root-context paste button above itself, which stays in the DOM and is
    // hidden by CSS — a `.first()` here would pick that one up.
    const multiPaste = multiBlock.locator('.block-paste[data-paste-ctx="multi"]')
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
  // The clipboard is cached per user, not per LiveView, so a copy has always
  // been readable from another entry. What was missing was the *visibility*
  // rule: `clipboard_meta` started nil on every BlockField mount, so a freshly
  // opened entry rendered no `data-paste-allow` and CSS hid every paste
  // button — the feature looked like it only worked inside one document.
  test('copy in one entry and paste into two others', async ({ page }) => {
    test.setTimeout(120000)

    // Target entries first, so they exist when we go looking for them
    await createPage(page, 'Cross Entry Target One', 'cross-entry-target-one')
    await savePage(page)
    await createPage(page, 'Cross Entry Target Two', 'cross-entry-target-two')
    await savePage(page)

    // Source entry with a block carrying an identifiable var value
    await createPage(page, 'Cross Entry Source', 'cross-entry-source')
    await page.getByRole('button', { name: 'Add block' }).click()
    await page.getByRole('button', { name: 'MEDIA' }).click()
    await page.getByRole('button', { name: 'Single Asset' }).click()
    await syncLV(page)

    const sourceBlock = page.locator('.entry-block').first()
    await sourceBlock.locator('.block-vars').getByLabel('String label').fill('Value From Source')
    await page.waitForTimeout(400)
    await syncLV(page)
    await savePage(page)

    await openPage(page, 'Cross Entry Source')
    await expect(page.locator('.entry-block')).toHaveCount(1)
    await copyBlock(page.locator('.entry-block').first())
    await syncLV(page)

    // First target: the paste affordance has to survive the navigation
    await openPage(page, 'Cross Entry Target One')
    await expect(page.locator('.entry-block')).toHaveCount(0)

    const bottomPaste = page.locator('.blocks-content > .block-plus-wrapper .block-paste')
    await expect(bottomPaste).toBeVisible()
    await bottomPaste.click()
    await syncLV(page)

    await expect(page.locator('.entry-block')).toHaveCount(1)
    await expect(
      page.locator('.entry-block').first().locator('.block-vars').getByLabel('String label')
    ).toHaveValue('Value From Source')
    await savePage(page)

    // Second target: one copy pastes into as many entries as you like — the
    // clipboard is not consumed by a paste
    await openPage(page, 'Cross Entry Target Two')
    const secondPaste = page.locator('.blocks-content > .block-plus-wrapper .block-paste')
    await expect(secondPaste).toBeVisible()
    await secondPaste.click()
    await syncLV(page)
    await expect(page.locator('.entry-block')).toHaveCount(1)
    await savePage(page)

    // Both pasted blocks persisted, and the source kept its own
    await openPage(page, 'Cross Entry Target One')
    await expect(page.locator('.entry-block')).toHaveCount(1)
    await expect(
      page.locator('.entry-block').first().locator('.block-vars').getByLabel('String label')
    ).toHaveValue('Value From Source')

    await openPage(page, 'Cross Entry Target Two')
    await expect(page.locator('.entry-block')).toHaveCount(1)

    await openPage(page, 'Cross Entry Source')
    await expect(page.locator('.entry-block')).toHaveCount(1)
  })

  // A block pasted under a different schema must be re-sourced to the target's
  // join table, or `list_orphaned_blocks/0` reads it as unreachable.
  test('copy a multi entry in a page and paste it into a project', async ({ page }) => {
    test.setTimeout(120000)

    await createPage(page, 'Cross Schema Source', 'cross-schema-source')
    await page.getByRole('button', { name: 'Add block' }).click()
    await page.getByRole('button', { name: 'COPY PASTE TEST' }).click()
    await page.getByRole('button', { name: 'Team Section' }).click()
    await syncLV(page)

    const sourceMulti = page.locator('[data-module-multi="true"]')
    await sourceMulti.locator('.block-plus').last().click()
    await page.getByRole('button', { name: 'COPY PASTE TEST' }).click()
    await page.getByRole('button', { name: /^Team Member\b/ }).click()
    await syncLV(page)

    const member = sourceMulti.locator('.block-children [data-uid]').first()
    await member.locator('.block-vars').getByLabel('Name').fill('Cross Schema Alice')
    await page.waitForTimeout(400)
    await syncLV(page)

    await copyBlock(member)
    await syncLV(page)

    // Over to a project — a different schema, a different block field
    await page.goto('/admin/projects/projects')
    await syncLV(page)
    await page.getByRole('link', { name: 'Test Project Alpha' }).click()
    await syncLV(page)

    await page.getByRole('button', { name: 'Add block' }).click()
    await page.getByRole('button', { name: 'COPY PASTE TEST' }).click()
    await page.getByRole('button', { name: 'Team Section' }).click()
    await syncLV(page)

    const targetMulti = page.locator('[data-module-multi="true"]')
    const multiPaste = targetMulti.locator('.block-paste[data-paste-ctx="multi"]')
    await expect(multiPaste.first()).toBeVisible()
    await multiPaste.first().click()
    await syncLV(page)

    const pasted = targetMulti.locator('.block-children [data-uid]').first()
    await expect(pasted.locator('.block-vars').getByLabel('Name')).toHaveValue('Cross Schema Alice')

    // No save here: the seeded projects are missing required fields (Client,
    // Introduction) that have nothing to do with blocks. Persistence of a
    // pasted block is covered by the page-to-page test above, and the source
    // rewrite by `Brando.Villain.DuplicationTest`.
  })
})
