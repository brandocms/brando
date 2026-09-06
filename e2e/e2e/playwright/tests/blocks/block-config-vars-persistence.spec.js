import { test, expect } from '../../test-support/setupAuth'
import { syncLV } from '../../utils'

// Config-placement vars have no inputs in the block body — only the config
// modal shows them. Since that modal lives INSIDE the block's
// `phx-change="validate_block"` form, its inputs are submitted on every
// keystroke anywhere in the block. Shorten or thin that list and
// `cast_assoc(:vars)` rebuilds the var from whatever params remain, blanking
// its key, placement and value.
//
// The failure is silent: the block keeps working, the content var saves fine,
// and the config var quietly empties on the next edit. Nothing else in the
// suite opens a block config modal, so this is the only thing pinning the rule
// — it matters most now that config chrome renders lazily rather than sitting
// hidden in the DOM for every block.
//
// `:hidden`-placement vars have no UI at all and round-trip through
// `carried_var/1`. On an *unsaved* block they have no primary key either, so
// identity-only params were not enough — Ecto rebuilt them blank. The module
// used here seeds one (`tracking_id`) so that path is covered too.
test.describe('Block config var persistence', () => {
  test.setTimeout(120000)

  const TITLE = 'Config var persistence'
  const URI = 'config-var-persistence'

  const configModal = (page) => page.locator('.modal.visible')

  const openConfig = async (page, block) => {
    await block.locator('.block-action-dropdown > .block-action').first().click()
    await block
      .locator('.block-action-dropdown-content button', { hasText: 'Configure' })
      .click()
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

  const reopenEntry = async (page) => {
    await page.getByRole('button', { name: 'Save', exact: true }).click()
    await expect(page).toHaveURL(/\/admin\/pages$/, { timeout: 30000 })
    await syncLV(page)
    await expect(page.locator('.alert.error')).not.toBeVisible({ timeout: 5000 })

    await page.getByRole('link', { name: `${TITLE} →` }).click()
    await syncLV(page)
  }

  test('config vars survive a closed-modal edit, save and reload', async ({
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
    await page.getByRole('button', { name: '08 CONFIG VAR TEST' }).click()
    await page.getByRole('button', { name: 'Config Vars' }).click()
    await syncLV(page)

    const block = page.locator('.entry-block [data-block-uid]').first()
    await expect(block).toBeVisible()

    // Content var — the one with an input in the block body.
    await block.locator('.block-vars').getByLabel('Body text').fill('Body one')
    await page.waitForTimeout(400)
    await syncLV(page)

    // Config var — only reachable with the modal open.
    await openConfig(page, block)
    await configModal(page).getByLabel('Config note').fill('Config one')
    await page.waitForTimeout(400)
    await syncLV(page)
    await configModal(page)
      .getByLabel('Block description')
      .fill('Described block')
    await page.waitForTimeout(400)
    await syncLV(page)
    await closeConfig(page)

    // The regression trigger: edit the block again with the modal CLOSED, so a
    // validate_block round trip runs while the config inputs are not rendered.
    await block.locator('.block-vars').getByLabel('Body text').fill('Body two')
    await page.waitForTimeout(400)
    await syncLV(page)

    await reopenEntry(page)

    const saved = page.locator('.entry-block [data-block-uid]').first()
    await expect(saved.locator('.block-vars').getByLabel('Body text')).toHaveValue(
      'Body two'
    )


    await openConfig(page, saved)

    // The Vars panel lists every var on the block by key. A var Ecto rebuilt
    // from thin params comes back with a nil key, so this is where blanking
    // shows up — including for `:hidden` vars, which have no input anywhere
    // else in the UI.
    await expect(configModal(page).locator('.var .key')).toHaveText([
      'body_text',
      'config_note',
      'tracking_id',
    ])

    await expect(configModal(page).getByLabel('Config note')).toHaveValue(
      'Config one'
    )
    await expect(configModal(page).getByLabel('Block description')).toHaveValue(
      'Described block'
    )

    // Second cycle: the var is persisted now, which is a different cast path
    // from the first save — the first ran against an unsaved var.
    await configModal(page).getByLabel('Config note').fill('Config two')
    await page.waitForTimeout(400)
    await syncLV(page)
    await closeConfig(page)

    await block.locator('.block-vars').getByLabel('Body text').fill('Body three')
    await page.waitForTimeout(400)
    await syncLV(page)

    await reopenEntry(page)

    const resaved = page.locator('.entry-block [data-block-uid]').first()
    await expect(
      resaved.locator('.block-vars').getByLabel('Body text')
    ).toHaveValue('Body three')
    await openConfig(page, resaved)
    await expect(configModal(page).getByLabel('Config note')).toHaveValue(
      'Config two'
    )
    await closeConfig(page)
  })
})
