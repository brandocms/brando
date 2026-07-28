import { test, expect } from '../../test-support/setupAuth'
import { syncLV } from '../../utils'

// A ref's config modal holds inputs for its `data` embed — heading level, id,
// link and so on. That chrome is now rendered only while the modal is open, so
// those inputs are absent from the block's `validate_block` form the rest of
// the time.
//
// That is only safe because ref data is an `embeds_one` under polymorphic_embed,
// where `cast` leaves fields the params don't mention alone. The block's `vars`
// are a `has_many`, where the same omission makes Ecto rebuild the record from
// whatever params remain — see block-config-vars-persistence.spec.js. The two
// associations behave differently, so both need their own round trip; this one
// pins the ref side.
test.describe('Block ref config persistence', () => {
  test.setTimeout(120000)

  const TITLE = 'Ref config persistence'
  const URI = 'ref-config-persistence'

  const configModal = (page) => page.locator('.modal.visible')

  const openRefConfig = async (page, refBlock) => {
    await refBlock.locator('.block-action.config').first().click()
    await syncLV(page)
    await expect(configModal(page)).toBeVisible()
  }

  const closeConfig = async (page) => {
    await configModal(page)
      .locator('.modal-footer button', { hasText: 'Close' })
      .click()
    await syncLV(page)
    await expect(page.locator('.modal.visible')).toHaveCount(0)
  }

  test('ref config fields survive a closed-modal edit, save and reload', async ({
    page,
  }) => {
    await page.goto('/admin')
    await page.getByRole('link', { name: 'Pages & Sections' }).click()
    await syncLV(page)
    await page.getByRole('link', { name: 'Create page' }).click()
    await syncLV(page)
    await page.getByLabel('Title', { exact: true }).fill(TITLE)
    await page.getByLabel('URI').fill(URI)

    await page.getByRole('button', { name: 'Add block' }).last().click()
    await page.getByRole('button', { name: '05 LIVE PREVIEW TEST' }).click()
    await page.getByRole('button', { name: 'Styled Header' }).click()
    await syncLV(page)

    const headerRef = page.locator('.base-block.ref-block').first()
    await expect(headerRef).toBeVisible()

    // Body input — always rendered, outside the config modal.
    const headerText = headerRef.locator('textarea').first()
    await headerText.fill('Heading one')
    await page.waitForTimeout(400)
    await syncLV(page)

    // Config-only fields: level, id, link.
    await openRefConfig(page, headerRef)
    await configModal(page).getByLabel('ID').fill('anchor-one')
    await page.waitForTimeout(400)
    await syncLV(page)
    await configModal(page).getByLabel('Link').fill('https://example.com/one')
    await page.waitForTimeout(400)
    await syncLV(page)
    await configModal(page).getByLabel('H3').check()
    await page.waitForTimeout(400)
    await syncLV(page)
    await closeConfig(page)

    // The regression trigger: edit the ref again with its config modal CLOSED,
    // so a validate_block round trip runs while those inputs are not rendered.
    await headerText.fill('Heading two')
    await page.waitForTimeout(400)
    await syncLV(page)

    await page.getByRole('button', { name: 'Save' }).click()
    await expect(page).toHaveURL(/\/admin\/pages$/, { timeout: 30000 })
    await syncLV(page)
    await expect(page.locator('.alert.error')).not.toBeVisible({ timeout: 5000 })

    await page.getByRole('link', { name: `${TITLE} →` }).click()
    await syncLV(page)

    const savedRef = page.locator('.base-block.ref-block').first()
    await expect(savedRef.locator('textarea').first()).toHaveValue('Heading two')

    await openRefConfig(page, savedRef)
    await expect(configModal(page).getByLabel('ID')).toHaveValue('anchor-one')
    await expect(configModal(page).getByLabel('Link')).toHaveValue(
      'https://example.com/one'
    )
    await expect(configModal(page).getByLabel('H3')).toBeChecked()
    await closeConfig(page)
  })
})
