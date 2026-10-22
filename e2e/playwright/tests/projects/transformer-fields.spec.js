import { test, expect } from '../../test-support/setupAuth'
import { syncLV } from '../../utils'

const rows = page => page.locator('[phx-hook="Brando.TransformerFields"]')
const field = (row, name) => row.locator(`[name="transformer_item[${name}]"]`)

async function createClient(page, overrides = {}) {
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
          featured: false, size: 's', kind: 'talk', tags: sequence === 0 ? ['red'] : ['blue'],
          ...overrides,
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
  await first.getByRole('checkbox').focus()
  await first.getByRole('checkbox').press('Space')
  await second.getByRole('radio', { name: 'M', exact: true }).check()
  await first.locator('[data-component=":select"]').getByRole('button', { name: 'Velg', exact: true }).click()
  await page.getByRole('dialog').getByRole('button', { name: 'Exhibition', exact: true }).click()
  await field(first, 'title').fill('Edited plain title')
  await saveAndReload(page, url)
  await expect(field(first, 'title')).toHaveValue('Edited plain title')
  await expect(first.getByRole('checkbox')).toBeChecked()
  await expect(second.getByRole('checkbox')).not.toBeChecked()
  await expect(field(first, 'kind')).toHaveValue('exhibition')
  await expect(field(second, 'kind')).toHaveValue('talk')
  await expect(second.getByRole('radio', { name: 'M', exact: true })).toBeChecked()
  await first.getByRole('checkbox').focus()
  await first.getByRole('checkbox').press('Space')
  await saveAndReload(page, url)
  await expect(first.getByRole('checkbox')).not.toBeChecked()
})

test('transformer array MultiSelect persists adding, removing and clearing selections in separate rows', async ({ page }) => {
  const url = await createClient(page)
  const first = rows(page).nth(0)
  const second = rows(page).nth(1)
  const tags = row => row.locator('input[name="transformer_item[tags][]"]')
  const toggleTags = async (row, labels) => {
    await row.locator('[data-component=":multi_select"]').getByRole('button', { name: 'Velg', exact: true }).click()
    const dialog = page.getByRole('dialog', { name: 'Velg alternativer', exact: true })
    for (const label of labels) {
      await dialog.getByRole('checkbox', { name: label, exact: true }).click()
      await syncLV(page)
    }
    await dialog.getByRole('button', { name: 'Lukk dialog', exact: true }).click()
    await expect(dialog).not.toBeVisible()
  }
  const expectTags = async (row, values) => {
    await expect.poll(() => tags(row).evaluateAll(inputs => inputs.map(input => input.value).filter(Boolean))).toEqual(values)
  }

  await toggleTags(first, ['Green'])
  await toggleTags(second, ['Red'])
  await saveAndReload(page, url)
  await expectTags(first, ['red', 'green'])
  await expectTags(second, ['blue', 'red'])

  await toggleTags(first, ['Red'])
  await toggleTags(second, ['Blue'])
  await saveAndReload(page, url)
  await expectTags(first, ['green'])
  await expectTags(second, ['red'])

  await toggleTags(first, ['Green'])
  await saveAndReload(page, url)
  await expectTags(first, [])
  await expectTags(second, ['red'])
})

test('transformer array selection survives a newer filter validation locking the form', async ({ page }) => {
  let hold = false
  const held = []
  const validations = []
  const updates = []
  let selectionRef
  let deliver
  const isReply = (message, ref) => {
    const [, replyRef, , event] = JSON.parse(message)
    return replyRef === ref && event === 'phx_reply'
  }
  await page.routeWebSocket('**/live/websocket*', socket => {
    const server = socket.connectToServer()
    socket.onMessage(message => {
      const [, ref, , event, payload] = JSON.parse(message)
      if (hold && event === 'event') {
        if (payload.event === 'validate') validations.push(ref)
        if (payload.event === 'select_option') selectionRef = ref
        if (payload.event === 'update_field' && payload.value.field === 'tags') updates.push(payload.value)
      }
      server.send(message)
    })
    server.onMessage(message => {
      if (hold) held.push(message)
      else socket.send(message)
    })
    deliver = ref => {
      while (held.length) {
        const message = held.shift()
        socket.send(message)
        if (isReply(message, ref)) break
      }
    }
  })
  const url = await createClient(page)
  const first = rows(page).nth(0)
  await first.locator('[data-component=":multi_select"]').getByRole('button', { name: 'Velg', exact: true }).click()
  await syncLV(page)
  const dialog = page.getByRole('dialog', { name: 'Velg alternativer', exact: true })
  const filter = dialog.locator('input[name="select-modal-search"]')
  hold = true
  await filter.fill('G')
  await expect.poll(() => validations.length).toBe(1)
  await expect.poll(() => held.some(message => isReply(message, validations[0]))).toBe(true)
  await dialog.getByRole('checkbox', { name: 'Green', exact: true }).click()
  await expect.poll(() => held.some(message => isReply(message, selectionRef))).toBe(true)
  await filter.pressSequentially('r')
  await expect.poll(() => validations.length).toBe(2)
  await expect.poll(() => held.some(message => isReply(message, validations[1]))).toBe(true)

  // Deliver through the selection reply in wire order, keeping the newer
  // validation outstanding. LiveView patches a locked clone of the form but
  // dispatches b:validate immediately, while the visible inputs still say red.
  deliver(selectionRef)
  await expect(page.locator('form.main-form')).toHaveAttribute('data-phx-ref-lock', /.+/)
  await expect.poll(() => updates.length).toBe(1)
  hold = false
  deliver()
  await syncLV(page)
  await dialog.getByRole('button', { name: 'Lukk dialog', exact: true }).click()
  await saveAndReload(page, url)
  const tags = row => row.locator('input[name="transformer_item[tags][]"]')
  await expect.poll(() => tags(first).evaluateAll(inputs => inputs.map(input => input.value).filter(Boolean))).toEqual(['red', 'green'])
  await expect.poll(() => tags(rows(page).nth(1)).evaluateAll(inputs => inputs.map(input => input.value).filter(Boolean))).toEqual(['blue'])
  expect(new URLSearchParams(updates[0].params).getAll('transformer_item[tags][]')).toEqual(['red', 'green'])
})

test('an earlier transformer reply cannot restore a removed string list member before the next keystroke', async ({ page }) => {
  await page.clock.install()
  let hold = false
  const held = []
  let release
  let editRef
  let editReplyHeld = false
  await page.routeWebSocket('**/live/websocket*', socket => {
    const server = socket.connectToServer()
    socket.onMessage(message => {
      const [, ref, , event, payload] = JSON.parse(message)
      if (hold && event === 'event' && payload.event === 'update_field' && payload.value.field === 'aliases') {
        editRef ??= ref
      }
      server.send(message)
    })
    server.onMessage(message => {
      if (hold) {
        held.push(message)
        const [, ref, , event] = JSON.parse(message)
        if (ref === editRef && event === 'phx_reply') editReplyHeld = true
      } else socket.send(message)
    })
    release = () => {
      hold = false
      for (const message of held.splice(0)) socket.send(message)
    }
  })
  const url = await createClient(page, { aliases: ['a', 'b', 'c'] })
  const first = rows(page).nth(0)
  const aliases = first.locator('input[name="transformer_item[aliases][]"]')
  hold = true
  await aliases.first().fill('edited a')
  // Wait for the debounced edit's actual reply before deleting b. Releasing
  // it inside the removal's 300 ms debounce could restore b's old row while
  // LiveView preserved the focused c, yielding [edited a, c, c, empty].
  await expect.poll(() => editReplyHeld).toBe(true)
  // Freeze the remaining debounce window, so even a slow CI worker delivers
  // the old reply and types the next key before a debounced removal can send.
  await page.clock.pauseAt(Date.now() + 100)
  await first.getByRole('button', { name: 'Fjern rad', exact: true }).nth(1).click()
  release()
  await expect(first).not.toHaveAttribute('data-phx-ref-lock', /.+/)
  await aliases.nth(1).press('ArrowRight')
  await aliases.nth(1).pressSequentially('z')
  await page.clock.resume()
  await saveAndReload(page, url)
  await expect.poll(() => aliases.evaluateAll(inputs => inputs.map(input => input.value))).toEqual(['edited a', 'cz', ''])
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
