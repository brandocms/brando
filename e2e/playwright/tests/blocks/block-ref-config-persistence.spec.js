import { test, expect } from '../../test-support/setupAuth'
import { syncLV } from '../../utils'

// A ref's config modal holds inputs for its `data` embed — heading level, id,
// link and so on. A polymorphic embed rebuilds from the params it is given, so
// those values must reach every `validate_block`, modal open or not. While it
// is closed, ref types that list their config fields (`carried_config` on
// `Block.Render.block/1`) send them as bare hidden inputs instead of the full
// widgets; the rest still render the whole config slot, hidden.
//
// The block's `vars` are a `has_many` with the same need — see
// block-config-vars-persistence.spec.js. This one pins the ref side.
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
      .locator('.modal-footer')
      .getByRole('button', { name: /^(Close|Done)$/ })
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
    await expect(page.locator('.module-picker-namespace.active')).toContainText('05 LIVE PREVIEW TEST')
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

    await page.getByTestId('submit').click()
    await expect(page).toHaveURL(/\/admin\/pages$/, { timeout: 30000 })
    await syncLV(page)
    await expect(page.locator('.alert.error')).not.toBeVisible({ timeout: 5000 })

    await page.getByRole('link', { name: TITLE, exact: true }).click()
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

  test('a text ref keeps its type through a closed-config edit, save and reload', async ({ page }) => {
    await page.goto('/admin')
    await page.getByRole('link', { name: 'Pages & Sections' }).click()
    await syncLV(page)
    await page.getByRole('link', { name: 'Create page' }).click()
    await syncLV(page)
    await page.getByLabel('Title', { exact: true }).fill(`${TITLE} text`)
    await page.getByLabel('URI').fill(`${URI}-text`)

    await page.getByRole('button', { name: 'Add block' }).last().click()
    await page.getByRole('button', { name: '05 LIVE PREVIEW TEST' }).click()
    await expect(page.locator('.module-picker-namespace.active')).toContainText('05 LIVE PREVIEW TEST')
    await page.getByRole('button', { name: 'Rich Text Article' }).click()
    await syncLV(page)

    const textRef = page.locator('.base-block.ref-block').first()
    await openRefConfig(page, textRef)
    await configModal(page).getByLabel('Lede').check()
    await page.waitForTimeout(400)
    await syncLV(page)
    await closeConfig(page)

    // Edit the ref with its config closed: only the carried values are sent.
    const editor = textRef.locator('.ProseMirror')
    await editor.click()
    await editor.press('ControlOrMeta+a')
    await page.keyboard.type('Edited with the config closed')
    await page.waitForTimeout(800)
    await syncLV(page)

    await page.getByTestId('submit').click()
    await expect(page).toHaveURL(/\/admin\/pages$/, { timeout: 30000 })
    await syncLV(page)
    await expect(page.locator('.alert.error')).not.toBeVisible({ timeout: 5000 })

    await page.getByRole('link', { name: `${TITLE} text`, exact: true }).click()
    await syncLV(page)

    const savedRef = page.locator('.base-block.ref-block').first()
    await expect(savedRef.locator('.ProseMirror')).toHaveText('Edited with the config closed')
    await openRefConfig(page, savedRef)
    await expect(configModal(page).getByLabel('Lede')).toBeChecked()
    await closeConfig(page)
  })

  // Media refs carry more kinds of config value: override text, radios,
  // toggles (checkboxes) and inherited playback overrides. Each one is set in
  // the modal, then the block is collapsed and expanded — two validate_block
  // round trips with the modal closed — saved and reloaded.
  // A toggle's checkbox is zero-sized behind its slider; its text label is
  // what a person clicks.
  const setToggle = async (modal, label, on) => {
    if ((await modal.getByLabel(label).isChecked()) !== on) {
      await modal.locator('label', { hasText: label }).first().click()
    }
    await expect(modal.getByLabel(label)).toBeChecked({ checked: on })
  }

  const MEDIA = [
    {
      type: 'picture',
      module: 'Single Image with Caption',
      set: async (modal) => {
        await modal.getByLabel('Alternative text').fill('Alt one')
        await modal.getByRole('tab', { name: 'Display' }).click()
        await modal.getByLabel('High', { exact: true }).check()
        await modal.getByLabel('Image CSS classes').fill('img-one')
      },
      check: async (modal) => {
        await expect(modal.getByLabel('Alternative text')).toHaveValue('Alt one')
        await modal.getByRole('tab', { name: 'Display' }).click()
        await expect(modal.getByLabel('High', { exact: true })).toBeChecked()
        await expect(modal.getByLabel('Image CSS classes')).toHaveValue('img-one')
      },
    },
    {
      type: 'video',
      module: 'Video Player',
      set: async (modal) => {
        await modal.getByRole('tab', { name: 'Playback' }).click()
        await modal.getByRole('switch', { name: 'Loop' }).click()
        await modal.getByRole('tab', { name: 'Display' }).click()
        await modal.getByLabel('Video CSS classes').fill('video-one')
        await modal.getByLabel('Opacity (0–100)').fill('40')
      },
      check: async (modal) => {
        await modal.getByRole('tab', { name: 'Playback' }).click()
        await expect(modal.getByRole('switch', { name: 'Loop' })).toHaveAttribute('aria-checked', 'true')
        await modal.getByRole('tab', { name: 'Display' }).click()
        await expect(modal.getByLabel('Video CSS classes')).toHaveValue('video-one')
        await expect(modal.getByLabel('Opacity (0–100)')).toHaveValue('40')
      },
    },
    {
      type: 'gallery',
      module: 'Gallery with Controls',
      set: async (modal) => {
        await modal.getByLabel('List', { exact: true }).check()
        await setToggle(modal, 'Lightbox', true)
        await modal.getByLabel('Class', { exact: true }).fill('gallery-one')
      },
      check: async (modal) => {
        await expect(modal.getByLabel('List', { exact: true })).toBeChecked()
        await expect(modal.getByLabel('Lightbox')).toBeChecked()
        await expect(modal.getByLabel('Class', { exact: true })).toHaveValue('gallery-one')
      },
    },
    {
      type: 'file',
      module: 'Media attachment',
      fixture: 'media-upload',
      set: async (modal) => {
        await modal.getByLabel('Description').fill('About the file')
        await setToggle(modal, 'Open in new window/tab', true)
        await setToggle(modal, 'Download instead of open', false)
      },
      check: async (modal) => {
        await expect(modal.getByLabel('Description')).toHaveValue('About the file')
        await expect(modal.getByLabel('Open in new window/tab')).toBeChecked()
        await expect(modal.getByLabel('Download instead of open')).not.toBeChecked()
      },
    },
  ]

  for (const { type, module, fixture, set, check } of MEDIA) {
    test(`a ${type} ref keeps its config through closed-config validates, save and reload`, async ({ page }) => {
      if (fixture) expect((await page.request.post(`/e2e/setup_fixtures/${fixture}`)).ok()).toBe(true)
      const title = `${TITLE} ${type}`

      await page.goto('/admin')
      await page.getByRole('link', { name: 'Pages & Sections' }).click()
      await syncLV(page)
      await page.getByRole('link', { name: 'Create page' }).click()
      await syncLV(page)
      await page.getByLabel('Title', { exact: true }).fill(title)
      await page.getByLabel('URI').fill(`${URI}-${type}`)

      await page.getByRole('button', { name: 'Add block' }).last().click()
      await page.getByRole('button', { name: '05 LIVE PREVIEW TEST' }).click()
      await expect(page.locator('.module-picker-namespace.active')).toContainText('05 LIVE PREVIEW TEST')
      await page.getByRole('button', { name: module, exact: true }).click()
      await syncLV(page)

      const ref = page.locator('.base-block.ref-block').first()
      await openRefConfig(page, ref)
      await set(configModal(page))
      await page.waitForTimeout(400)
      await syncLV(page)
      await closeConfig(page)

      // The block's own collapse toggle is in its form: each click submits the
      // whole form, with this ref's config closed.
      const toggler = page.locator('.entry-block').first().locator('.block-actions label.toggler').first()
      for (let i = 0; i < 2; i++) {
        await toggler.click()
        await syncLV(page)
      }

      await page.getByTestId('submit').click()
      await expect(page).toHaveURL(/\/admin\/pages$/, { timeout: 30000 })
      await syncLV(page)
      await expect(page.locator('.alert.error')).not.toBeVisible({ timeout: 5000 })

      await page.getByRole('link', { name: title, exact: true }).click()
      await syncLV(page)

      await openRefConfig(page, page.locator('.base-block.ref-block').first())
      await check(configModal(page))
      await closeConfig(page)
    })
  }
})
