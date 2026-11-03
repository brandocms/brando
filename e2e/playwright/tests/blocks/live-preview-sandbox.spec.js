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

  // morphdom's loader would hand itself to the site's module loader and leave
  // its global unset, and the preview would stop following the form. The
  // loaders mark the page if anything is handed to them.
  for (const [name, loader] of [
    [
      'an AMD loader',
      () => {
        window.define = function () {
          document.documentElement.dataset.loaderUsed = 'define'
        }
        window.define.amd = {}
      }
    ],
    [
      'CommonJS globals',
      () => {
        window.exports = {}
        window.module = {
          set exports(_value) {
            document.documentElement.dataset.loaderUsed = 'module'
          }
        }
      }
    ]
  ]) {
    test(`a site with ${name} still has its preview updated`, async ({ page }) => {
      const errors = watchErrors(page)
      await page.addInitScript(`if (!location.pathname.startsWith('/admin')) (${loader})()`)
      await openPreview(page, 'Sandbox Loader')

      const preview = getPreviewFrame(page)
      await page.locator('.header-block textarea').fill('Loader Header')
      await syncLV(page)
      await expect(preview.locator('header[b-tpl="styled-header"] h1')).toContainText('Loader Header')
      await expect(preview.locator('html')).not.toHaveAttribute('data-loader-used')
      expect(errors).toEqual([])
    })
  }

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

  // Runs `setup(arg)` in the preview page once it has a `<body>`, before the
  // client script the plug puts at its end, as the site's own scripts and
  // content would be there.
  const beforeClient = (page, setup, arg) =>
    page.addInitScript(
      `if (location.pathname.startsWith('/__livepreview')) new MutationObserver((_, observer) => {
        if (!document.body) return
        observer.disconnect()
        ;(${setup})(${JSON.stringify(arg)})
      }).observe(document, { childList: true, subtree: true })`
    )

  // The site's classic scripts share one global scope with the client. Names
  // they declare must not keep the client from loading, and the client must
  // leave the site's globals as they were.
  test('a site script declaring the names the client uses keeps its globals and its preview updated', async ({
    page
  }) => {
    const errors = watchErrors(page)
    await beforeClient(page, () => {
      const script = document.createElement('script')
      // `self` is where phoenix.js looks for `WebSocket`, and a site's `let`
      // replaces it for every classic script after
      script.textContent =
        "let token = 'site token'; const body = 'site body'; var Phoenix = 'site Phoenix'; var morphdom = 'site morphdom'; let self = 'site self'"
      document.body.append(script)
    })
    await openPreview(page, 'Sandbox Globals')

    const preview = getPreviewFrame(page)
    await page.locator('.header-block textarea').fill('Globals Header')
    await syncLV(page)
    await expect(preview.locator('header[b-tpl="styled-header"] h1')).toContainText('Globals Header')

    const frame = await (await page.locator('#live-preview-frame').elementHandle()).contentFrame()
    expect(await frame.evaluate(() => [token, body, window.Phoenix, window.morphdom, self])).toEqual([
      'site token',
      'site body',
      'site Phoenix',
      'site morphdom',
      'site self'
    ])
    expect(errors).toEqual([])
  })

  // Error monitoring and other SDKs wrap DOM methods on their prototypes, and
  // their wrappers call the original with the `this` they were called with.
  // That must be the real window or document, which the native method accepts.
  test('a site script wrapping DOM methods keeps its preview updated', async ({ page }) => {
    const clientErrors = []
    page.on('pageerror', error => {
      if (/__livepreview\/client-/.test(error.stack || '')) clientErrors.push(error.message)
    })
    await beforeClient(page, () => {
      const addEventListener = EventTarget.prototype.addEventListener
      EventTarget.prototype.addEventListener = function (...args) {
        return addEventListener.apply(this, args)
      }
      const createElement = Document.prototype.createElement
      Document.prototype.createElement = function (...args) {
        return createElement.apply(this, args)
      }
    })
    await openPreview(page, 'Sandbox Wrapped')

    const preview = getPreviewFrame(page)
    await page.locator('.header-block textarea').fill('Wrapped Header')
    await syncLV(page)
    await expect(preview.locator('header[b-tpl="styled-header"] h1')).toContainText('Wrapped Header')
    await expect(page.locator('.live-preview-notice')).toBeEmpty()
    expect(clientErrors).toEqual([])
  })

  // A wrapper defined on the object itself with `Object.defineProperty` is
  // neither writable nor configurable, and a proxy of that object would have
  // to return it unbound.
  test('a site script defining DOM methods on the document and window keeps its preview updated', async ({
    page
  }) => {
    const clientErrors = []
    page.on('pageerror', error => {
      if (/__livepreview\/client-/.test(error.stack || '')) clientErrors.push(error.message)
    })
    await beforeClient(page, () => {
      const createElement = document.createElement
      Object.defineProperty(document, 'createElement', {
        value: function (...args) {
          return createElement.apply(this, args)
        }
      })
      const addEventListener = window.addEventListener
      Object.defineProperty(window, 'addEventListener', {
        value: function (...args) {
          return addEventListener.apply(this, args)
        }
      })
    })
    await openPreview(page, 'Sandbox Defined')

    const preview = getPreviewFrame(page)
    await page.locator('.header-block textarea').fill('Defined Header')
    await syncLV(page)
    await expect(preview.locator('header[b-tpl="styled-header"] h1')).toContainText('Defined Header')
    await expect(page.locator('.live-preview-notice')).toBeEmpty()
    expect(clientErrors).toEqual([])
  })

  // Content can name an element after a member of `document` (rich text keeps
  // `name`), and `document` then returns the element for that name. (By the
  // spec the name also hides what `window` inherits from EventTarget; Chromium
  // keeps those, so the `addEventListener` case here is `document`'s.) The
  // client starts and patches anyway.
  for (const name of ['querySelector', 'createElement', 'createRange', 'addEventListener']) {
    test(`an element named ${name} in the content keeps the preview updating`, async ({ page }) => {
      const clientErrors = []
      page.on('pageerror', error => {
        if (/__livepreview\/client-/.test(error.stack || '')) clientErrors.push(error.message)
      })
      await beforeClient(
        page,
        name => {
          const image = document.createElement('img')
          image.name = name
          document.body.prepend(image)
        },
        name
      )
      await openPreview(page, `Sandbox Named ${name}`)

      const preview = getPreviewFrame(page)
      await page.locator('.header-block textarea').fill(`Named ${name}`)
      await syncLV(page)
      await expect(preview.locator('header[b-tpl="styled-header"] h1')).toContainText(`Named ${name}`)
      await expect(page.locator('.live-preview-notice')).toBeEmpty()
      expect(clientErrors).toEqual([])
    })
  }
})
