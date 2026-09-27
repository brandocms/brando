import { readFile, writeFile } from 'node:fs/promises'
import { createRequire } from 'node:module'
import assert from 'node:assert/strict'

const require = createRequire(new URL('../../../e2e/playwright/package.json', import.meta.url))
const { chromium } = require('@playwright/test')
const local = path => new URL(path, import.meta.url)
const read = path => readFile(local(path), 'utf8')
const embed = async (path, type) => `data:${type};base64,${(await readFile(local(path))).toString('base64')}`

// A portable copy keeps the actual consumer fonts and repository Heroicons.
let html = await read('index.html')
let css = await read('styles.css')
let js = await read('preview.js')
const icons = await read('../../../assets/css/heroicons.css')
const iconNames = ['link', 'document-text', 'x-mark', 'check', 'magnifying-glass']
const iconCSS = iconNames.map(name => icons.match(new RegExp(`\\.hero-${name} \\{[\\s\\S]*?\\n\\}`))[0]).join('\n')
for (const weight of ['Regular', 'Medium']) {
  const path = `../../../e2e/assets/backend/public/fonts/Main-${weight}.woff2`
  css = css.replace(path, await embed(path, 'font/woff2'))
}
for (const photo of ['architecture', 'room']) {
  const path = `../content-agent-concepts/media/${photo}.jpg`
  js = js.replace(path, await embed(path, 'image/jpeg'))
}
html = html.replace('<link rel="stylesheet" href="../../../assets/css/heroicons.css">', `<style>${iconCSS}</style>`)
html = html.replace('<link rel="stylesheet" href="styles.css">', `<style>${css}</style>`)
html = html.replace('<script src="preview.js"></script>', `<script>${js}</script>`)
await writeFile(local('standalone.html'), html)

const browser = await chromium.launch({ headless: true })
try {
  const page = await browser.newPage({ viewport: { width: 1640, height: 1020 }, deviceScaleFactor: 1 })
  const errors = []
  page.on('pageerror', error => errors.push(error.message))
  await page.goto(local('standalone.html').href)
  await page.evaluate(() => document.fonts.ready)
  await page.locator('img').evaluateAll(images => Promise.all(images.map(image => image.decode())))
  await page.screenshot({ path: local('comparison-desktop.png').pathname, fullPage: true })
  for (const id of ['a', 'b', 'c', 'd']) {
    await page.locator(`button[data-view="${id}"]`).click()
    await page.mouse.move(0, 0)
    await page.locator(`#variant-${id}`).screenshot({ path: local(`variant-${id}-desktop.png`).pathname })
    await page.setViewportSize({ width: 390, height: 1000 })
    assert(await page.evaluate(() => document.documentElement.scrollWidth <= innerWidth), `${id}: mobile overflow`)
    await page.locator(`#variant-${id}`).screenshot({ path: local(`variant-${id}-mobile.png`).pathname })
    await page.setViewportSize({ width: 1640, height: 1020 })
  }
  await page.locator('button[data-view="d"]').click()
  const variant = page.locator('#variant-d')
  await variant.getByRole('button', { name: 'Remove Havglimt retreat' }).click()
  assert.equal(await variant.locator('.entry-field .identifier').count(), 1)
  await variant.getByRole('button', { name: 'Clear all', exact: true }).click()
  assert.equal(await variant.locator('.entry-field .identifier').count(), 0)
  await variant.getByRole('button', { name: 'Select entries', exact: true }).click()
  await variant.getByRole('searchbox').fill('quieter')
  assert.equal(await variant.locator('.picker .identifier').count(), 1)
  await variant.locator('.picker .identifier').press('Enter')
  assert.equal(await variant.locator('.entry-field .identifier').count(), 1)
  await variant.getByRole('searchbox').fill('')
  await page.getByRole('button', { name: 'Reset preview', exact: true }).click()
  assert.equal(await variant.locator('.entry-field .identifier').count(), 2)
  assert.deepEqual(errors, [])
  console.log('Captured all four global identifier variants at desktop/mobile widths; joined cover-row controls checked.')
} finally {
  await browser.close()
}
