import { test, expect } from '../../test-support/setupAuth'
import { syncLV } from '../../utils'

// While a ref's config modal is closed, its fields travel as bare hidden
// inputs (`carried_config` on `Block.Render.block/1`) instead of the widgets
// the modal renders. Each ref type lists those fields by hand, so a field
// added to a config slot but not to its list would be dropped on the next
// validate. This compares what the block form submits with the config closed
// and open, decoded the way the server decodes it: they must be identical.
const MODULES = [
  { module: 'Styled Header' },
  { module: 'Rich Text Article' },
  { module: 'Single Image with Caption' },
  { module: 'Video Player' },
  { module: 'Gallery with Controls' },
  { module: 'Map Embed' },
  { module: 'Media attachment', fixture: 'media-upload' },
]

// Last value wins for a plain name, `[]` names collect, as in Plug.
const submitted = (page) =>
  page.locator('form[phx-change="validate_block"]').first().evaluate((form) => {
    const params = {}
    for (const [name, value] of new FormData(form)) {
      if (value instanceof File) continue
      if (name.endsWith('[]')) (params[name] ||= []).push(value)
      else params[name] = value
    }
    return params
  })

test.describe('Carried ref config', () => {
  test.setTimeout(90000)

  for (const { module, fixture } of MODULES) {
    test(`${module}: the block submits the same params with its config closed and open`, async ({ page }) => {
      if (fixture) expect((await page.request.post(`/e2e/setup_fixtures/${fixture}`)).ok()).toBe(true)

      await page.goto('/admin/pages/create')
      await syncLV(page)
      await page.getByRole('button', { name: 'Add block', exact: true }).click()
      await page.getByRole('button', { name: '05 LIVE PREVIEW TEST' }).click()
      await expect(page.locator('.module-picker-namespace.active')).toContainText('05 LIVE PREVIEW TEST')
      await page.getByRole('button', { name: module, exact: true }).click()
      await syncLV(page)

      const closed = await submitted(page)

      await page.locator('.base-block.ref-block').first().locator('.block-action.config').first().click()
      await syncLV(page)
      await expect(page.locator('.modal.visible')).toBeVisible()
      const open = await submitted(page)

      expect(Object.keys(closed).length).toBeGreaterThan(0)
      expect(closed).toEqual(open)
    })
  }
})
