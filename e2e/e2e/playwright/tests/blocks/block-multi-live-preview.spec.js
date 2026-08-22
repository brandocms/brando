import { test, expect } from '../../test-support/setupAuth'
import {
  syncLV,
  toggleLivePreview,
  getPreviewFrame,
  waitForPreviewReady,
  waitForPreviewUpdate
} from '../../utils'

// Live preview coverage for MULTI modules and their children. The existing
// live-preview suite only exercises flat root blocks, so a multi module's
// children — which render through the annotated `[+:C<uid>]` content slot
// rather than as their own root blocks — had no regression net.
test.describe('Live Preview with multi modules', () => {
  test.setTimeout(60000)

  const createPage = async (page, title, uri) => {
    await page.goto('/admin')
    await page.getByRole('link', { name: 'Pages & Sections' }).click()
    await syncLV(page)
    await page.getByRole('link', { name: 'Create page' }).click()
    await syncLV(page)
    await page.getByLabel('Title', { exact: true }).fill(title)
    await page.getByLabel('URI').fill(uri)
  }

  const addTeamSection = async page => {
    await page.getByRole('button', { name: 'Add block' }).last().click()
    await page.getByRole('button', { name: 'COPY PASTE TEST' }).click()
    await page.getByRole('button', { name: 'Team Section' }).click()
  }

  const addChild = async (page, multiBlock, name) => {
    await multiBlock.locator('.block-plus').last().click()
    await page.getByRole('button', { name: 'COPY PASTE TEST' }).click()
    await page.getByRole('button', { name: new RegExp(`^${name}\\b`) }).click()
  }

  test('inserting a child while the preview is open renders it', async ({ page }) => {
    await createPage(page, 'Multi Preview Insert', 'multi-preview-insert')

    await toggleLivePreview(page)
    await waitForPreviewReady(page)
    const frame = getPreviewFrame(page)

    await addTeamSection(page)
    await waitForPreviewUpdate(page)
    await expect(frame.locator('section[b-tpl="team-section"]')).toBeAttached({ timeout: 15000 })

    const multiBlock = page.locator('[data-module-multi="true"]').first()
    await addChild(page, multiBlock, 'Team Member')
    await waitForPreviewUpdate(page)
    await expect(frame.locator('div[b-tpl="team-member"]')).toBeAttached({ timeout: 15000 })

    const memberBlock = multiBlock.locator('.block-children [data-uid]').first()
    await memberBlock.locator('.block-vars').getByLabel('Name').fill('Ada Lovelace')
    await page.waitForTimeout(600)
    await waitForPreviewUpdate(page)
    await expect(frame.locator('div[b-tpl="team-member"] h3')).toHaveText('Ada Lovelace', {
      timeout: 15000
    })
  })

  test('opening the preview after the fact shows existing children', async ({ page }) => {
    await createPage(page, 'Multi Preview Late', 'multi-preview-late')

    await addTeamSection(page)
    await syncLV(page)

    const multiBlock = page.locator('[data-module-multi="true"]').first()
    await addChild(page, multiBlock, 'Team Member')
    await syncLV(page)

    await toggleLivePreview(page)
    await waitForPreviewReady(page)
    const frame = getPreviewFrame(page)
    await expect(frame.locator('div[b-tpl="team-member"]')).toBeAttached({ timeout: 15000 })

    const memberBlock = multiBlock.locator('.block-children [data-uid]').first()
    await memberBlock.locator('.block-vars').getByLabel('Name').fill('Grace Hopper')
    await page.waitForTimeout(600)
    await waitForPreviewUpdate(page)
    await expect(frame.locator('div[b-tpl="team-member"] h3')).toHaveText('Grace Hopper', {
      timeout: 15000
    })
  })

  test('a multi module nested in a container updates its children', async ({ page }) => {
    await createPage(page, 'Multi Preview Container', 'multi-preview-container')

    await page.getByRole('button', { name: 'Add block' }).click()
    await page.getByRole('button', { name: 'Container' }).click()
    await syncLV(page)

    const container = page.locator('[data-block-type="container"]')
    await container.locator('.block-plus').first().click()
    await page.getByRole('button', { name: 'COPY PASTE TEST' }).click()
    await page.getByRole('button', { name: 'Team Section' }).click()
    await syncLV(page)

    await toggleLivePreview(page)
    await waitForPreviewReady(page)
    const frame = getPreviewFrame(page)
    await expect(frame.locator('section[b-tpl="team-section"]')).toBeAttached({ timeout: 15000 })

    const multiBlock = page.locator('[data-module-multi="true"]').first()
    await addChild(page, multiBlock, 'Team Member')
    await waitForPreviewUpdate(page)
    await expect(frame.locator('div[b-tpl="team-member"]')).toBeAttached({ timeout: 15000 })

    const memberBlock = multiBlock.locator('.block-children [data-uid]').first()
    await memberBlock.locator('.block-vars').getByLabel('Name').fill('Alan Turing')
    await page.waitForTimeout(600)
    await waitForPreviewUpdate(page)
    await expect(frame.locator('div[b-tpl="team-member"] h3')).toHaveText('Alan Turing', {
      timeout: 15000
    })
  })

  test('children survive a save and reopen', async ({ page }) => {
    await createPage(page, 'Multi Preview Saved', 'multi-preview-saved')

    await addTeamSection(page)
    await syncLV(page)
    await addChild(page, page.locator('[data-module-multi="true"]').first(), 'Team Member')
    await syncLV(page)

    await page.getByRole('button', { name: 'Save' }).click()
    await expect(page).toHaveURL(/\/admin\/pages$/, { timeout: 30000 })
    await syncLV(page)
    await page.getByRole('link', { name: 'Multi Preview Saved →' }).click()
    await syncLV(page)

    await toggleLivePreview(page)
    await waitForPreviewReady(page)
    const frame = getPreviewFrame(page)
    await expect(frame.locator('div[b-tpl="team-member"]')).toBeAttached({ timeout: 15000 })

    const memberBlock = page
      .locator('[data-module-multi="true"]')
      .first()
      .locator('.block-children [data-uid]')
      .first()
    await memberBlock.locator('.block-vars').getByLabel('Name').fill('Katherine Johnson')
    await page.waitForTimeout(600)
    await waitForPreviewUpdate(page)
    await expect(frame.locator('div[b-tpl="team-member"] h3')).toHaveText('Katherine Johnson', {
      timeout: 15000
    })
  })

  // "Team Lead" is an entry template that is itself flagged `multi: true` —
  // a shape real projects produce, and one where the block carries multi=true
  // while never taking children of its own.
  test('a child whose module is itself flagged multi renders and updates', async ({ page }) => {
    await createPage(page, 'Multi Preview Nested Flag', 'multi-preview-nested-flag')

    await toggleLivePreview(page)
    await waitForPreviewReady(page)
    const frame = getPreviewFrame(page)

    await addTeamSection(page)
    await waitForPreviewUpdate(page)

    const multiBlock = page.locator('[data-module-multi="true"]').first()
    await addChild(page, multiBlock, 'Team Lead')
    await waitForPreviewUpdate(page)
    await expect(frame.locator('div[b-tpl="team-lead"]')).toBeAttached({ timeout: 15000 })

    const leadBlock = multiBlock.locator('.block-children [data-uid]').first()
    await leadBlock.locator('.block-vars').getByLabel('Lead name').fill('Ada Lovelace')
    await page.waitForTimeout(600)
    await waitForPreviewUpdate(page)
    await expect(frame.locator('div[b-tpl="team-lead"] h3')).toHaveText('Ada Lovelace', {
      timeout: 15000
    })
  })
})
