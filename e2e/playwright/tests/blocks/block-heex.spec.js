import { test, expect } from '../../test-support/setupAuth'
import {
  syncLV,
  toggleLivePreview,
  getPreviewFrame,
  waitForPreviewReady,
  waitForPreviewUpdate
} from '../../utils'

test.describe('HEEx blocks', () => {
  test('render vars, refs and system assigns in the editor and live preview', async ({ page }) => {
    await page.goto('/admin')
    await page.getByRole('link', { name: 'Pages & Sections' }).click()
    await syncLV(page)

    await page.getByRole('link', { name: 'Create page' }).click()
    await syncLV(page)

    await page.getByLabel('Title', { exact: true }).fill('HEEx Test Page')
    await page.getByLabel('URI').fill('heex-test')

    await page.getByRole('button', { name: 'Add block' }).click()
    await page.getByRole('button', { name: '05 LIVE PREVIEW TEST' }).click()
    await page.getByRole('button', { name: 'HEEx Parity' }).click()
    await syncLV(page)

    const editorPreview = page.locator('.block-heex-preview article[b-tpl="heex-parity"]')
    await expect(editorPreview).toBeVisible()
    await expect(editorPreview).toHaveAttribute('data-language', 'en')
    await expect(editorPreview).toHaveAttribute('data-identity', 'Organization name')
    await expect(editorPreview.locator('.heex-entry-title')).toHaveText('HEEx Test Page')
    await expect(editorPreview.locator('.heex-ref-type')).toHaveText('text')
    await expect(editorPreview.locator('.heex-translation')).toHaveText('Translated')
    await expect(editorPreview.locator('video[data-video]')).toHaveAttribute(
      'src',
      'https://cdn.example/video.mp4'
    )

    const headline = page.locator('.block-vars').getByLabel('Headline')
    await headline.fill('Updated HEEx headline')
    await syncLV(page)
    await expect(editorPreview.locator('.heex-headline')).toHaveText('Updated HEEx headline')

    await toggleLivePreview(page)
    await waitForPreviewReady(page)

    const frame = getPreviewFrame(page)
    const published = frame.locator('article[b-tpl="heex-parity"]')

    await expect(published).toHaveAttribute('data-language', 'en')
    await expect(published).toHaveAttribute('data-identity', 'Organization name')
    await expect(published.locator('.heex-headline')).toHaveText('Updated HEEx headline')
    await expect(published.locator('.heex-entry-title')).toHaveText('HEEx Test Page')
    await expect(published.locator('.paragraph')).toContainText('HEEx body')
    await expect(published.locator('.heex-headless-title')).toHaveText('Headless title')
    await expect(published.locator('h3')).toHaveCount(0)
    await expect(published.locator('.heex-route')).toHaveText('/about/team')
    await expect(published.locator('.heex-translation')).toHaveText('Translated')
    await expect(published.getByRole('region', { name: 'Video Player' })).toBeVisible()

    await headline.fill('Live HEEx update')
    await waitForPreviewUpdate(page)
    await expect(published.locator('.heex-headline')).toHaveText('Live HEEx update')

    await page.locator('.field-wrapper:has-text("Show entry title") .slider').click()
    await waitForPreviewUpdate(page)
    await expect(published.locator('.heex-entry-title')).toHaveCount(0)
  })
})
