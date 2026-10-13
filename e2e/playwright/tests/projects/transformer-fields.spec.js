import { test, expect } from '../../test-support/setupAuth'
import { syncLV } from '../../utils'

const rows = page => page.locator('[phx-hook="Brando.TransformerFields"]')
const field = (row, name) => row.locator(`[name="transformer_item[${name}]"]`)

async function createClient(page) {
  expect((await page.request.post('/e2e/setup_fixtures/norwegian-admin-user')).ok()).toBe(true)
  const response = await page.request.post('/__e2e/db/factory', {
    data: {
      schema: 'E2eProject.Projects.Client', creator_id: 1, fields: ['id'],
      attributes: {
        name: 'Transformer fields', slug: 'transformer-fields', status: 'draft', language: 'en',
        inline_rows: ['First', 'Second'].map((title, sequence) => ({
          title, sequence, status: 'published', aliases: [`${title} one`, `${title} two`],
          label: { en: `${title} label`, no: `${title} merkelapp`, de: `${title} Beschriftung` },
          description: { en: `${title} description`, no: `${title} beskrivelse`, de: `${title} Beschreibung` },
          featured: false, size: 's', kind: 'talk',
        })),
      },
    },
  })
  expect(response.ok(), await response.text()).toBe(true)
  const { id } = await response.json()
  const url = `/admin/projects/clients/transformer/${id}`
  await page.goto(url)
  await syncLV(page)
  await expect(rows(page)).toHaveCount(2)
  return url
}

async function saveAndReload(page, url) {
  await page.getByTestId('submit').click()
  await expect(page).toHaveURL(/\/admin\/projects\/clients$/)
  await page.goto(url)
  await syncLV(page)
  await expect(rows(page)).toHaveCount(2)
}

test('transformer translations survive unrelated edits, an immediate save and reload in separate rows', async ({ page }) => {
  const url = await createClient(page)
  const first = rows(page).nth(0)
  const second = rows(page).nth(1)

  await field(first, 'label][en').fill('Edited first label')
  await first.locator('.i18n-text').getByRole('tab', { name: 'no', exact: true }).click()
  await field(first, 'label][no').fill('Ny merkelapp')
  await field(second, 'description][en').fill('Edited second\ndescription')
  await page.locator('input[name="client[name]"]').fill('Unrelated client edit')
  await field(second, 'title').fill('Edited second title')
  // Save inside the hook's debounce: all pending row/field values must go first.
  await saveAndReload(page, url)

  await expect(field(first, 'label][en')).toHaveValue('Edited first label')
  await expect(field(first, 'label][no')).toHaveValue('Ny merkelapp')
  await expect(field(first, 'label][de')).toHaveValue('First Beschriftung')
  await expect(field(first, 'description][en')).toHaveValue('First description')
  await expect(field(second, 'label][en')).toHaveValue('Second label')
  await expect(field(second, 'description][en')).toHaveValue('Edited second\ndescription')
  await expect(field(second, 'description][no')).toHaveValue('Second beskrivelse')
  await expect(field(second, 'description][de')).toHaveValue('Second Beschreibung')
  await expect(field(second, 'title')).toHaveValue('Edited second title')
  await expect(page.locator('input[name="client[name]"]')).toHaveValue('Unrelated client edit')

  await field(first, 'label][en').fill('')
  await field(second, 'description][en').fill('')
  await saveAndReload(page, url)
  await expect(field(first, 'label][en')).toHaveValue('')
  await expect(field(first, 'label][no')).toHaveValue('Ny merkelapp')
  await expect(field(first, 'label][de')).toHaveValue('First Beschriftung')
  await expect(field(second, 'description][en')).toHaveValue('')
  await expect(field(second, 'description][no')).toHaveValue('Second beskrivelse')
})

test('simple transformer controls still save to their own row', async ({ page }) => {
  const url = await createClient(page)
  const first = rows(page).nth(0)
  const second = rows(page).nth(1)
  await first.getByRole('checkbox').check()
  await second.getByRole('radio', { name: 'M', exact: true }).check()
  await first.locator('.multiselect').getByRole('button', { name: 'Velg', exact: true }).click()
  await page.getByRole('dialog').getByRole('button', { name: 'Exhibition', exact: true }).click()
  await field(first, 'title').fill('Edited plain title')
  await saveAndReload(page, url)
  await expect(field(first, 'title')).toHaveValue('Edited plain title')
  await expect(first.getByRole('checkbox')).toBeChecked()
  await expect(second.getByRole('checkbox')).not.toBeChecked()
  await expect(field(first, 'kind')).toHaveValue('exhibition')
  await expect(field(second, 'kind')).toHaveValue('talk')
  await expect(second.getByRole('radio', { name: 'M', exact: true })).toBeChecked()
  await first.getByRole('checkbox').uncheck()
  await saveAndReload(page, url)
  await expect(first.getByRole('checkbox')).not.toBeChecked()
})

test('transformer string lists save additions, removals and clearing without changing another row', async ({ page }) => {
  const url = await createClient(page)
  const first = rows(page).nth(0)
  const second = rows(page).nth(1)
  const aliases = row => row.locator('input[name="transformer_item[aliases][]"]')
  const expectAliases = async (row, values) => {
    await expect(aliases(row)).toHaveCount(values.length)
    for (const [index, value] of values.entries()) await expect(aliases(row).nth(index)).toHaveValue(value)
  }

  await aliases(first).last().fill('Added alias')
  await saveAndReload(page, url)
  await expectAliases(first, ['First one', 'First two', 'Added alias', ''])
  await expectAliases(second, ['Second one', 'Second two', ''])

  await first.getByRole('button', { name: 'Fjern rad', exact: true }).nth(1).click()
  await saveAndReload(page, url)
  await expectAliases(first, ['First one', 'Added alias', ''])

  await first.getByRole('button', { name: 'Fjern rad', exact: true }).first().click()
  await first.getByRole('button', { name: 'Fjern rad', exact: true }).first().click()
  await saveAndReload(page, url)
  await expectAliases(first, [''])
  await expectAliases(second, ['Second one', 'Second two', ''])
})
