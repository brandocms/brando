import { test, expect } from '../../test-support/setupAuth'
import { syncLV } from '../../utils'

async function factory(page, schema, attributes) {
  const response = await page.request.post('/__e2e/db/factory', { data: { schema, attributes, creator_id: 1, fields: ['id'] } })
  expect(response.ok(), await response.text()).toBeTruthy()
  return response.json()
}

// The gallery field's actions measure their own room (a container query in
// Gallery.css): in a wide field every button has its label, in a narrow one
// the Select buttons keep only their icons. Labels stay the accessible names
// and titles, so the structure is checked rather than the translated copy.
test('the gallery field keeps its actions on one row, labelled where they fit', async ({ page }) => {
  const client = await factory(page, 'E2eProject.Projects.Client', { name: 'Gallery client', slug: 'gallery-client', status: 'published', language: 'en' })
  const project = await factory(page, 'E2eProject.Projects.Project', {
    title: 'Gallery actions', slug: 'gallery-actions', client_id: client.id, status: 'published', language: 'en', introduction: '<p>Intro</p>',
  })

  await page.setViewportSize({ width: 1440, height: 1000 })
  await page.goto(`/admin/projects/projects/update/${project.id}`)
  await syncLV(page)

  const actions = page.locator('.gallery-input .gallery-actions .actions')
  const buttons = actions.getByRole('button')
  await expect(buttons).toHaveCount(3)

  const layout = () => actions.evaluate(el => {
    const rows = new Set([...el.querySelectorAll('.media-button')].map(b => Math.round(b.getBoundingClientRect().top)))
    const labels = [...el.querySelectorAll('.media-button-label')].map(l => l.getBoundingClientRect().width > 2)
    const buttonsWrap = [...el.querySelectorAll('.media-button')].some(b => b.getBoundingClientRect().height > 40)
    return { rows: rows.size, labels, buttonsWrap }
  })

  for (const button of await buttons.all()) {
    const label = await button.locator('.media-button-label').textContent()
    await expect(button).toHaveAttribute('title', label.trim())
    await expect(button).toHaveAccessibleName(label.trim())
  }

  expect(await layout()).toEqual({ rows: 1, labels: [true, true, true], buttonsWrap: false })

  await page.setViewportSize({ width: 390, height: 900 })
  await expect.poll(layout).toEqual({ rows: 1, labels: [true, false, false], buttonsWrap: false })
})
