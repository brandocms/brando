import { test, expect } from '../../test-support/setupAuth'
import {
  syncLV,
  toggleLivePreview,
  getPreviewFrame,
  waitForPreviewReady,
  waitForPreviewUpdate
} from '../../utils'

// Switching a ref off is a content decision the module template reacts to:
// `{% if refs.<name>.active == false %}` swaps in a fallback, commonly one
// pulled from a link var's identifier via `get_entry`. That chain crosses the
// ref toggle, `Parser.process_refs/1`, the liquid `active` check, var identifier
// preloading and the live-preview broadcast, and had no coverage.
test.describe('Ref active toggles and template fallbacks', () => {
  test.setTimeout(90000)

  const addMediaObject = async page => {
    await page.goto('/admin')
    await page.getByRole('link', { name: 'Pages & Sections' }).click()
    await syncLV(page)
    await page.getByRole('link', { name: 'Create page' }).click()
    await syncLV(page)
    await page.getByLabel('Title', { exact: true }).fill('Ref Fallback Test')
    await page.getByLabel('URI').fill('ref-fallback-test')

    await page.getByRole('button', { name: 'Add block' }).last().click()
    await page.getByRole('button', { name: 'REF FALLBACK TEST' }).click()
    await page.getByRole('button', { name: 'Fallback Group' }).click()
    await syncLV(page)

    const multiBlock = page.locator('[data-module-multi="true"]').first()
    await multiBlock.locator('.block-plus').last().click()
    await page.getByRole('button', { name: 'REF FALLBACK TEST' }).click()
    await page.getByRole('button', { name: /^Fallback Object\b/ }).click()
    await syncLV(page)

    return multiBlock.locator('.block-children [data-uid]').first()
  }

  test('both a ref and a headless_ref expose a working on/off switch', async ({ page }) => {
    const childBlock = await addMediaObject(page)

    // `{% ref %}` and `{% headless_ref %}` both have to place an editable ref
    const refBlocks = childBlock.locator('.base-block.ref-block')
    await expect(refBlocks).toHaveCount(2)

    const mediaRef = childBlock.locator('.base-block.ref-block.picture').first()
    const textRef = childBlock.locator('.base-block.ref-block.text').first()
    await expect(mediaRef).not.toHaveClass(/disabled/)
    await expect(textRef).not.toHaveClass(/disabled/)

    await mediaRef.locator('.block-toolbar .switch .slider').first().click()
    await syncLV(page)
    await expect(mediaRef).toHaveClass(/disabled/)

    await textRef.locator('.block-toolbar .switch .slider').first().click()
    await syncLV(page)
    await expect(textRef).toHaveClass(/disabled/)
  })

  test('switching refs off swaps in the template fallbacks in live preview', async ({ page }) => {
    const childBlock = await addMediaObject(page)

    await toggleLivePreview(page)
    await waitForPreviewReady(page)
    const frame = getPreviewFrame(page)

    const article = frame.locator('article[b-tpl="fallback-object"]')
    await expect(article).toBeAttached({ timeout: 15000 })
    await expect(frame.locator('.text')).toContainText('Caption body')
    await expect(frame.locator('.media-fallback')).not.toBeAttached()

    // No identifier picked yet, so the media fallback is the generic branch
    await childBlock.locator('.base-block.ref-block.picture .block-toolbar .switch .slider').first().click()
    await syncLV(page)
    await waitForPreviewUpdate(page)
    await expect(frame.locator('.media-fallback')).toBeAttached({ timeout: 15000 })

    // `{% headless_ref %}` reacts to its own switch the same way
    await childBlock.locator('.base-block.ref-block.text .block-toolbar .switch .slider').first().click()
    await syncLV(page)
    await waitForPreviewUpdate(page)
    await expect(frame.locator('.text-fallback')).toBeAttached({ timeout: 15000 })
  })

  test('the fallback resolves an entry through the link var identifier', async ({ page }) => {
    const childBlock = await addMediaObject(page)

    // Point the link var at a content identifier
    await childBlock.locator('.input-link .link-preview').first().click()
    await syncLV(page)

    const linkModal = page.locator('[id$="-link-config"]').first()
    await expect(linkModal).toBeVisible()
    await linkModal.locator('.radios-wrapper').getByText('Identifier').click()
    await syncLV(page)
    await linkModal.locator('.button-group-vertical.tiny button', { hasText: 'Cases' }).click()
    await syncLV(page)
    await linkModal.locator('.identifier-options .identifier').first().click()
    await syncLV(page)
    await linkModal.locator('.modal-close').click()
    await syncLV(page)

    await toggleLivePreview(page)
    await waitForPreviewReady(page)
    const frame = getPreviewFrame(page)
    await expect(frame.locator('article[b-tpl="fallback-object"]')).toBeAttached({ timeout: 15000 })

    await childBlock.locator('.base-block.ref-block.picture .block-toolbar .switch .slider').first().click()
    await syncLV(page)
    await waitForPreviewUpdate(page)

    // `get_entry` resolved the identifier, so the entry branch wins over the
    // generic fallback and renders the entry's own title
    await expect(frame.locator('.entry-fallback')).toHaveText('Test Project Alpha', { timeout: 15000 })
    await expect(frame.locator('.media-fallback')).not.toBeAttached()
  })
})
