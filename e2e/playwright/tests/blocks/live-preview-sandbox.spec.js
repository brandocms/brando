import path from 'path'
import { test, expect } from '../../test-support/setupAuth'
import { syncLV, toggleLivePreview, getPreviewFrame, waitForPreviewReady } from '../../utils'

// Live previews hold editor content and are served sandboxed
// (`Brando.Plug.LivePreview`): their scripts run in an opaque origin, apart
// from the admin page that frames or opens them and from the viewer's cookies.
// The site's own scripts, fonts and the preview's updates keep working.
const PROBE = path.join(__dirname, '../../fixtures/preview-sandbox-probe.js')
const SESSION_COOKIE = '_e2e_project_key'

test.describe('Live preview sandbox', () => {
  test.setTimeout(60000)

  const openPreview = async (page, title) => {
    await page.goto('/admin/pages/create')
    await syncLV(page)
    await page.getByLabel('Title', { exact: true }).fill(title)
    await page.getByLabel('URI').fill(title.toLowerCase().replaceAll(' ', '-'))
    await page.getByRole('button', { name: 'Add block' }).click()
    await page.getByRole('button', { name: '05 LIVE PREVIEW TEST' }).click()
    await expect(page.locator('.module-picker-namespace.active')).toContainText('05 LIVE PREVIEW TEST')
    await page.getByRole('button', { name: 'Styled Header' }).click()
    await syncLV(page)
    await toggleLivePreview(page)
    await waitForPreviewReady(page)
  }

  // Errors the site's scripts throw where storage, cookies or a cross-origin
  // load is refused
  const watchErrors = (page, errors = []) => {
    page.on('pageerror', error => errors.push(error.message))
    page.on('console', message => {
      if (message.type() === 'error' && /SecurityError|CORS|Access-Control|access storage/i.test(message.text())) {
        errors.push(message.text())
      }
    })
    return errors
  }

  // The site's Vite module bundle ran through its Jupiter boot (which reads
  // cookies for its consent banner), and the footer's font loaded, preload included
  const expectSiteFrontend = async frame => {
    await expect(frame.locator('body[data-app-ready]')).toBeAttached()
    await expect
      .poll(() =>
        frame.evaluate(async () => {
          await document.fonts.ready
          return [...document.fonts].filter(font => font.family.includes('E2E Sans')).map(font => font.status)
        })
      )
      .toEqual(['loaded'])
  }

  test('script in the preview reaches neither the admin page nor the viewer session', async ({ page }) => {
    const errors = watchErrors(page)
    await openPreview(page, 'Sandbox Probe')

    const preview = getPreviewFrame(page)
    const heading = preview.locator('header[b-tpl="styled-header"] h1')
    await expect(heading).toContainText('Header Text')
    const frame = await (await page.locator('#live-preview-frame').elementHandle()).contentFrame()
    expect(await frame.evaluate(() => self.origin)).toBe('null')
    await expectSiteFrontend(frame)
    expect(errors).toEqual([])

    // The same request from the admin page carries the session cookie
    const controlRequest = page.waitForRequest(request => request.url().includes('preview-sandbox-control'))
    await page.evaluate(() => fetch('/admin?preview-sandbox-control', { mode: 'no-cors', credentials: 'include' }))
    expect((await (await controlRequest).allHeaders()).cookie).toContain(SESSION_COOKIE)

    const probeRequest = page.waitForRequest(request => request.url().includes('preview-sandbox-probe'))
    await frame.addScriptTag({ path: PROBE })
    await expect(preview.locator('html[data-sandbox-probe]')).toBeAttached()
    const probe = JSON.parse(await preview.locator('html').getAttribute('data-sandbox-probe'))
    expect(probe).toEqual({
      origin: 'null',
      parentDocument: 'SecurityError',
      topDocument: 'SecurityError',
      opener: 'none',
      adminFetch: 'TypeError',
    })
    const cookies = (await (await probeRequest).allHeaders()).cookie || ''
    expect(cookies).not.toContain(SESSION_COOKIE)

    // Updates arrive over the preview's socket from origin null
    await page.locator('.header-block textarea').fill('Sandboxed Header')
    await syncLV(page)
    await expect(heading).toContainText('Sandboxed Header')

    // The page asks the admin page to load it again (the channel's `reload`),
    // which sends the viewer's cookies: the preview is served, not refused
    await frame.evaluate(() => {
      document.documentElement.dataset.beforeReload = 'true'
      window.parent.postMessage({ source: 'brando-live-preview', type: 'reload' }, location.origin)
    })
    await expect(preview.locator('html[data-before-reload]')).toHaveCount(0)
    await expect(heading).toContainText('Sandboxed Header')

    // None but the probe's refused admin request
    expect(errors.filter(error => !error.includes("/admin' from origin 'null'"))).toEqual([])
  })

  // Without the endpoint's preview socket line the server refuses the socket
  // (and its log names the line): the drawer says so instead of showing a
  // preview that silently stops following the form. Here the page's socket
  // fails as a refused upgrade does (an error and a close, never open) until
  // the test lets it through.
  test('a preview whose socket is refused says live updates are unavailable', async ({ page }) => {
    await page.addInitScript(() => {
      const NativeWebSocket = window.WebSocket
      window.WebSocket = function (url, protocols) {
        if (!String(url).includes('/__livepreview/socket/') || window.__allowPreviewSocket) {
          return new NativeWebSocket(url, protocols)
        }
        const refused = new EventTarget()
        Object.assign(refused, { readyState: 0, url: String(url), send() {}, close() {} })
        setTimeout(() => {
          refused.readyState = 3
          for (const type of ['error', 'close']) {
            const event = type === 'close' ? new CloseEvent('close', { code: 1006 }) : new Event('error')
            refused.dispatchEvent(event)
            refused['on' + type]?.(event)
          }
        })
        return refused
      }
      Object.assign(window.WebSocket, { CONNECTING: 0, OPEN: 1, CLOSING: 2, CLOSED: 3 })
    })

    await openPreview(page, 'Sandbox Unavailable')
    const notice = page.locator('.live-preview-notice')
    await expect(notice).toHaveText(await notice.getAttribute('data-unavailable-message'))
    await expect(getPreviewFrame(page).locator('#lp-connection-status')).toBeVisible()

    // Once it connects, the notice goes
    const frame = await (await page.locator('#live-preview-frame').elementHandle()).contentFrame()
    await frame.evaluate(() => (window.__allowPreviewSocket = true))
    await expect(notice).toBeEmpty({ timeout: 15000 })
    await expect(getPreviewFrame(page).locator('#lp-connection-status')).toHaveCount(0)
  })

  test('the standalone preview has no opener and keeps updating', async ({ page }) => {
    const errors = watchErrors(page)
    await openPreview(page, 'Sandbox Window')

    const opened = page.context().waitForEvent('page')
    await page.getByRole('button', { name: 'Open preview in new window' }).click()
    const standalone = await opened
    watchErrors(standalone, errors)
    await expect(standalone.locator('header[b-tpl="styled-header"] h1')).toContainText('Header Text')

    expect(await standalone.evaluate(() => [self.origin, window.opener])).toEqual(['null', null])
    await expectSiteFrontend(standalone.mainFrame())

    await page.locator('.header-block textarea').fill('Standalone Header')
    await syncLV(page)
    await expect(standalone.locator('header[b-tpl="styled-header"] h1')).toContainText('Standalone Header')

    await standalone.close()
    expect(errors).toEqual([])
  })
})
