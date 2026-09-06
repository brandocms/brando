import { test, expect } from '../../test-support/setupAuth'
import { syncLV, toggleLivePreview, getPreviewFrame, waitForPreviewReady } from '../../utils'

for (const syntax of ['liquid', 'heex']) {
  for (const nested of [false, true]) {
    test(`${syntax} regions retain unsaved content after owner reactivation${nested ? ' inside a container' : ''}`, async ({ page }) => {
      test.setTimeout(90000)
      const name = `Region preview ${syntax}`
      const ref = name => ({
        name, description: name, uid: `preview-${syntax}-${name}`,
        data: { type: 'blocks', data: { module_set: 'Footnotes' } },
      })
      const response = await page.request.post('/__e2e/db/factory', {
        data: {
          schema: 'Brando.Content.Module', creator_id: 1, fields: ['id'],
          attributes: {
            name: { en: name, no: name }, namespace: { en: '09 NOTES & REGIONS', no: '09 NOTES & REGIONS' },
            help_text: { en: 'Preview fixture' }, class: 'region-preview', type: syntax,
            code: syntax === 'liquid'
              ? '<article class="region-preview"><aside>{% ref refs.sidebar %}</aside><section>{% ref refs.related %}</section></article>'
              : '<article class="region-preview"><aside><.ref block={@block} ref={:sidebar} /></aside><section><.ref block={@block} ref={:related} /></section></article>',
            refs: [ref('sidebar'), ref('related')], vars: [], multi: false, datasource: false,
          },
        },
      })
      expect(response.ok(), await response.text()).toBeTruthy()
      await page.goto('/admin/pages/create')
      await syncLV(page)
      await page.getByLabel('Title', { exact: true }).fill(name)
      await page.getByLabel('URI', { exact: true }).fill(`regions-${syntax}-${nested}`)
      await page.getByRole('button', { name: 'Add block', exact: true }).click()
      if (nested) {
        await page.getByRole('button', { name: 'Container', exact: true }).click()
        await syncLV(page)
        await page.locator('[data-block-type="container"] .block-plus').first().click()
      }
      await page.getByRole('button', { name, exact: true }).click()
      await syncLV(page)

      const drawer = page.locator('.block-slot-drawer.visible')
      const setText = async (editor, text) => {
        await editor.click()
        await expect(editor).toBeFocused()
        await editor.press('ControlOrMeta+a')
        await editor.press('Backspace')
        await page.keyboard.insertText(text)
        await expect(editor).toHaveText(text)
      }
      const addText = async text => {
        const count = await drawer.locator('.tiptap[contenteditable=true]').count()
        await drawer.getByRole('button', { name: 'Add block', exact: true }).last().click()
        await page.getByRole('button', { name: 'Note text', exact: true }).click()
        await expect(drawer.locator('.tiptap[contenteditable=true]')).toHaveCount(count + 1)
        await setText(drawer.locator('.tiptap[contenteditable=true]').last(), text)
        await syncLV(page)
      }
      await page.getByRole('button', { name: 'sidebar Edit blocks · Footnotes', exact: true }).click()
      await addText('First sidebar block')
      await addText('Second sidebar block')
      await drawer.getByRole('button', { name: 'Done', exact: true }).click()
      await page.getByRole('button', { name: 'related Edit blocks · Footnotes', exact: true }).click()
      await addText('Related block')
      await drawer.getByRole('button', { name: 'Done', exact: true }).click()

      await toggleLivePreview(page)
      await waitForPreviewReady(page)
      const frame = getPreviewFrame(page)
      await expect(frame.locator('.region-preview aside p')).toHaveText(['First sidebar block', 'Second sidebar block'])
      await page.getByRole('button', { name: 'sidebar Edit blocks · Footnotes', exact: true }).click()
      await setText(drawer.locator('.tiptap[contenteditable=true]').first(), 'Unsaved sidebar edit')
      await drawer.getByRole('button', { name: 'Done', exact: true }).click()
      await expect(frame.locator('.region-preview aside p')).toHaveText(['Unsaved sidebar edit', 'Second sidebar block'])

      // Disabling the owner hides its region buttons; keep addressing the
      // stable block UID when toggling it back on.
      const ownerUid = await page.getByRole('button', {
        name: 'sidebar Edit blocks · Footnotes', exact: true,
      }).evaluate(button => button.closest('.block').dataset.blockUid)
      const owner = page.locator(`.block[data-block-uid="${ownerUid}"]`)
      const toggle = owner.locator('.switch.small.inverse .slider').first()
      await toggle.click()
      await expect(frame.locator('.region-preview')).toHaveCount(0)
      await toggle.click()
      await expect(frame.locator('.region-preview aside p')).toHaveText(['Unsaved sidebar edit', 'Second sidebar block'])
      await expect(frame.locator('.region-preview section p')).toHaveText(['Related block'])
      await expect(frame.locator('body')).not.toContainText('[$ slot:')
      await expect(frame.locator('body')).not.toContainText('[$ content $]')
    })
  }
}
