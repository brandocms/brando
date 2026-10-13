import { test, expect } from '../../test-support/setupAuth'
import { syncLV } from '../../utils'

test('unlisted translations survive unrelated edits and clearing configured languages, including nested variables', async ({ page }) => {
  expect((await page.request.post('/e2e/setup_fixtures/norwegian-admin-user')).ok()).toBe(true)
  const response = await page.request.post('/__e2e/db/factory', {
    data: {
      schema: 'Brando.Content.Module', creator_id: 1, fields: ['id'],
      attributes: {
        name: { en: 'Translations', no: 'Oversettelser', de: 'Übersetzungen' },
        namespace: { en: 'Tests', no: 'Tester' },
        help_text: { en: 'Help', no: 'Hjelp', de: 'Erste Zeile\nZweite Zeile', fr: 'Aide & détails' },
        class: 'unlisted-translations', type: 'liquid', code: '<p>{{ caption }}</p>',
        refs: [], multi: false, datasource: false,
        vars: [{
          type: 'string', key: 'caption', placement: 'content', width: 'full',
          label: { en: 'Caption', no: 'Bildetekst', de: 'Beschriftung', fr: 'Légende' },
        }],
      },
    },
  })
  expect(response.ok(), await response.text()).toBe(true)
  const { id } = await response.json()
  const url = `/admin/config/content/modules/update/${id}`
  const variable = page.locator('#module-default-var-0')

  async function openVariable() {
    await page.getByRole('tab', { name: /^Variabler/ }).click()
    await page.getByRole('button', { name: 'Rediger variabelen caption', exact: true }).click()
    await variable.getByRole('tab', { name: 'Definisjon', exact: true }).click()
  }

  async function saveAndReload() {
    await variable.getByRole('button', { name: 'Ferdig', exact: true }).click()
    await page.locator('.module-editor-actions').getByRole('button', { name: /^Lagre/ }).click()
    await expect(page).toHaveURL(/\/admin\/config\/content\/modules$/)
    await page.goto(url)
    await syncLV(page)
  }

  async function retainedTranslations() {
    await expect(page.locator('input[name="module[name][de]"]')).toHaveValue('Übersetzungen')
    await expect(page.locator('input[name="module[help_text][de]"]')).toHaveValue('Erste Zeile\nZweite Zeile')
    await expect(page.locator('input[name="module[help_text][fr]"]')).toHaveValue('Aide & détails')
    await openVariable()
    await expect(variable.locator('input[name$="[label][de]"]')).toHaveValue('Beschriftung')
    await expect(variable.locator('input[name$="[label][fr]"]')).toHaveValue('Légende')
  }

  await page.goto(url)
  await syncLV(page)
  // Neither edit touches a translated field, but both submit the form's
  // current language maps. The nested label must survive the patches too.
  await page.getByLabel('CSS-klasse', { exact: true }).fill('unlisted-translations-edited')
  await syncLV(page)
  await openVariable()
  await variable.locator('input[name$="[placeholder]"]').fill('Unrelated variable edit')
  await syncLV(page)
  await saveAndReload()
  await expect(page.getByLabel('CSS-klasse', { exact: true })).toHaveValue('unlisted-translations-edited')
  await retainedTranslations()
  await expect(variable.locator('input[name$="[placeholder]"]')).toHaveValue('Unrelated variable edit')

  // A configured language is editable: preserving the unlisted ones must
  // not restore text the editor explicitly clears.
  await variable.getByRole('textbox', { name: 'Merkelapp (English)', exact: true }).fill('')
  await variable.getByRole('button', { name: 'Ferdig', exact: true }).click()
  await page.getByRole('tab', { name: 'Oversikt', exact: true }).click()
  await page.getByRole('textbox', { name: 'Navn (English)', exact: true }).fill('')
  await page.getByRole('textbox', { name: 'Hjelpetekst (English)', exact: true }).fill('')
  await openVariable()
  await saveAndReload()
  await expect(page.getByRole('textbox', { name: 'Navn (English)', exact: true })).toHaveValue('')
  await expect(page.getByRole('textbox', { name: 'Hjelpetekst (English)', exact: true })).toHaveValue('')
  await retainedTranslations()
  await expect(variable.getByRole('textbox', { name: 'Merkelapp (English)', exact: true })).toHaveValue('')
})
