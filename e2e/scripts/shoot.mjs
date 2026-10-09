#!/usr/bin/env node
// Screenshots of a running E2E server for UI work and PR descriptions: every
// shot at every width and admin language, as name-<locale>-<width>.png in
// <out>/<label>/. Use it instead of writing a one-off Playwright script.
//
//   cd e2e
//   BRANDO_E2E_INSTANCE=my_task scripts/server.sh start
//   node scripts/shoot.mjs --instance my_task --label before --shot dashboard=/admin
//   node scripts/shoot.mjs --instance my_task --label after --spec shots.json
//   BRANDO_E2E_INSTANCE=my_task scripts/server.sh stop
//
// Options (the CLI overrides the spec):
//   --spec <file>         JSON, or a JS module with a default export (below)
//   --shot <name>=<path>  add a shot; repeatable
//   --only <a,b>          take only these shots from the spec
//   --instance <name>     E2E instance: the URL comes from e2e/.envrc with
//                         BRANDO_E2E_INSTANCE=<name> (default: the current
//                         BRANDO_E2E_BASE_URL, else the worktree's instance)
//   --base <url>          server URL, instead of an instance
//   --out <dir>           default e2e/playwright/test-results/shots
//   --label <name>        subfolder, usually before or after (default after)
//   --widths <a,b>        default 1440,390
//   --locales <a,b>       admin languages, en and/or no (default en)
//   --email / --password  log in as someone else (default the E2E admin)
//   --no-sandbox          keep what setup and actions write (see Data below)
//   --hide-toasts         hide toast notifications
//   --no-unstick          leave sticky and fixed elements alone (see Overlays)
//
// Spec (all keys optional except shots[].name and shots[].path):
//   {
//     "label": "after", "widths": [1440, 390], "locales": ["en", "no"],
//     "fullPage": true,               // default for shots; false = viewport
//     "height": 1000,                 // viewport height (390 wide: 844)
//     "unstick": true,                // default; false = shots as rendered (Overlays)
//     "keep": [".selected-rows"],     // more overlays to leave alone (Overlays)
//     "setup": [                      // run before logging in, per locale/width
//       { "fixture": "assistant-applied-copy" },        // /e2e/setup_fixtures/<name>
//       { "post": "/e2e/admin-workspace-fixtures" },
//       { "factory": "E2eProject.Projects.Client", "as": "client",
//         "attributes": { "name": "Fjord", "slug": "fjord", "status": "published", "language": "en" } },
//       // "oban_testing": "manual" keeps the jobs a save schedules (publishing,
//       // expiry) instead of running them at once
//       { "factory": "Brando.Pages.Page", "oban_testing": "manual",
//         "attributes": { "title": "Later", "uri": "later", "status": "pending", "publish_at": "2030-01-01T09:00:00Z" } }
//     ],
//     "shots": [
//       { "name": "dashboard", "path": "/admin" },
//       { "name": "client", "path": "/admin/projects/clients/update/{client.id}" },
//       { "name": "page-meta", "path": "/admin/pages/update/1",
//         "actions": [{ "click": ".form-tool-meta" }, { "waitFor": "[id$='-meta-drawer']" }, { "wait": 400 }] },
//       { "name": "utilities-system", "path": "/admin/config/utils", "element": ".utils-system" },
//       { "name": "block", "path": "/admin/pages/update/1", "element": "[data-block-type='text']", "unstick": false },
//       { "name": "top", "path": "/admin", "fullPage": false, "widths": [1440], "locales": ["en"] },
//       { "name": "corner", "path": "/admin", "clip": { "x": 0, "y": 0, "width": 600, "height": 300 } }
//     ]
//   }
//
// Actions run in order after the page has loaded and LiveView has connected,
// and the script waits for LiveView to settle after each one:
//   { "click": sel } { "hover": sel } { "fill": sel, "value": "text" }
//   { "select": sel, "value": "option" } { "press": "Escape", "on": sel? }
//   { "waitFor": sel, "state": "visible"|"hidden"|"attached" } { "wait": ms }
//   { "scroll": sel } { "scroll": { "y": 800 } } { "scroll": "bottom" }
//   { "goto": path } { "evaluate": "js expression" }
// Each action waits up to 20s; add "timeout": ms to change that.
// A selector is any Playwright selector: CSS, `role=button[name="Meta"]`,
// `text=Save`. The first visible match is used. Any value may be a
// per-language object, e.g. { "en": "text=Save", "no": "text=Lagre" }; prefer
// test ids and classes. `{as.field}` in paths and values is replaced with
// setup results.
//
// Data: each locale/width combination runs in its own SQL sandbox, like an E2E
// test, so setup rows, Norwegian users and anything an action saves are rolled
// back afterwards and every combination starts from the seeded database. For
// the no locale the `admin-language-no` fixture switches the E2E admin's
// language inside the sandbox, so it still sees what it owns; it needs the
// sandbox. Setup steps run before the login (fixtures log in their own user).
//
// Overlays: before an element or full-page shot, sticky elements are put back
// in the flow (position: relative), so a sticky entry toolbar no longer sits
// over the element or across the middle of a full page. Element shots also
// hide fixed elements (headers, floating buttons, the presence bar), which
// would otherwise be painted over the element; full-page shots keep them, so
// the sidebar stays, and are taken from the top of the page, since one
// captured while scrolled has the fixed elements again at the scroll position
// over a black band. Left alone: modals, drawers, dialogs and popovers
// (dropdowns, tooltips) and whatever is inside them, the shot
// element's ancestors and, for fixed elements, its descendants. "keep" adds
// selectors to that list; "unstick": false (per spec or shot, or
// --no-unstick) turns it off. Viewport and clip shots are never changed.
//
// Chromium always runs with --font-render-hinting=none (default hinting on
// Linux makes text cramped). Committed design references come from
// playwright/scripts/admin-ui-references.mjs instead.
import { spawnSync } from 'node:child_process'
import { existsSync, mkdirSync, readFileSync } from 'node:fs'
import { createRequire } from 'node:module'
import path from 'node:path'
import { fileURLToPath, pathToFileURL } from 'node:url'

const here = path.dirname(fileURLToPath(import.meta.url))
const e2eDir = path.resolve(here, '..')
const playwrightDir = path.join(e2eDir, 'playwright')
const require = createRequire(path.join(playwrightDir, 'package.json'))

// Overlays an element or full-page shot leaves alone (see Overlays above).
const KEEP_OVERLAYS = [
  'dialog', '[role="dialog"]', '[role="alertdialog"]', '[role="tooltip"]', '[popover]',
  '.modal', '.modal-backdrop', '.drawer', '[class*="-drawer"]',
]
const DEFAULT_EMAIL = 'admin@brandocms.com'
const DEFAULT_PASSWORD = 'brandocms'
const LV_TIMEOUT = 20000

const fail = message => {
  console.error(message)
  process.exit(1)
}

function parseArgs(argv) {
  const opts = { shots: [] }
  const take = (i, name) => {
    if (argv[i + 1] === undefined) fail(`${name} needs a value`)
    return argv[i + 1]
  }
  for (let i = 0; i < argv.length; i++) {
    const arg = argv[i]
    switch (arg) {
      case '--help': case '-h': opts.help = true; break
      case '--spec': opts.spec = take(i++, arg); break
      case '--shot': {
        const value = take(i++, arg)
        const at = value.indexOf('=')
        if (at < 1) fail(`--shot expects <name>=<path>, got ${value}`)
        opts.shots.push({ name: value.slice(0, at), path: value.slice(at + 1) })
        break
      }
      case '--only': opts.only = take(i++, arg).split(',').filter(Boolean); break
      case '--instance': opts.instance = take(i++, arg); break
      case '--base': opts.base = take(i++, arg); break
      case '--out': opts.out = take(i++, arg); break
      case '--label': opts.label = take(i++, arg); break
      case '--widths': opts.widths = take(i++, arg).split(',').map(Number); break
      case '--locales': opts.locales = take(i++, arg).split(',').filter(Boolean); break
      case '--email': opts.email = take(i++, arg); break
      case '--password': opts.password = take(i++, arg); break
      case '--no-sandbox': opts.sandbox = false; break
      case '--hide-toasts': opts.hideToasts = true; break
      case '--no-unstick': opts.unstick = false; break
      default: fail(`Unknown option ${arg}. Run with --help.`)
    }
  }
  return opts
}

async function loadSpec(file) {
  if (!file) return {}
  const full = path.resolve(file)
  if (!existsSync(full)) fail(`No spec at ${full}`)
  if (full.endsWith('.json')) return JSON.parse(readFileSync(full, 'utf8'))
  const mod = await import(pathToFileURL(full).href)
  return mod.default || mod
}

// The URL .envrc derives for an instance (port from the instance name).
function instanceBase(instance) {
  const env = { ...process.env }
  for (const key of ['BRANDO_E2E_PORT', 'BRANDO_E2E_BASE_URL', 'BRANDO_E2E_DATABASE', 'BRANDO_URL_PORT', 'PORT']) delete env[key]
  if (instance) env.BRANDO_E2E_INSTANCE = instance
  const result = spawnSync('bash', ['-c', 'source .envrc >/dev/null && printf "%s" "$BRANDO_E2E_BASE_URL"'], { cwd: e2eDir, env, encoding: 'utf8' })
  if (result.status !== 0 || !result.stdout) fail(`Could not source ${path.join(e2eDir, '.envrc')}: ${result.stderr}`)
  return result.stdout
}

function resolveBase(opts, spec) {
  if (opts.base || spec.base) return (opts.base || spec.base).replace(/\/$/, '')
  const instance = opts.instance || spec.instance
  if (!instance && process.env.BRANDO_E2E_BASE_URL) return process.env.BRANDO_E2E_BASE_URL.replace(/\/$/, '')
  return instanceBase(instance || process.env.BRANDO_E2E_INSTANCE)
}

async function ensureServer(base, instance) {
  try {
    const response = await fetch(`${base}/admin/login`, { signal: AbortSignal.timeout(10000) })
    if (response.status >= 500) throw new Error(`HTTP ${response.status}`)
  } catch (error) {
    const name = instance ? `BRANDO_E2E_INSTANCE=${instance} ` : ''
    fail([
      `No E2E server answers at ${base} (${error.cause?.code || error.message}).`,
      'Start one in the background, then run this again:',
      `  cd ${e2eDir} && ${name}scripts/server.sh start`,
      `Stop it afterwards with: ${name}scripts/server.sh stop`,
    ].join('\n'))
  }
}

// Per-language values: { en: …, no: … } picks the current locale.
const localized = (value, locale) =>
  value && typeof value === 'object' && !Array.isArray(value) && (locale in value || 'en' in value) && Object.keys(value).every(k => /^[a-z]{2}$/.test(k))
    ? (value[locale] ?? value.en)
    : value

const interpolate = (value, vars) =>
  typeof value === 'string'
    ? value.replace(/\{([\w.]+)\}/g, (match, key) => {
      const found = key.split('.').reduce((acc, part) => (acc == null ? undefined : acc[part]), vars)
      return found === undefined ? match : String(found)
    })
    : value

async function settle(page, timeout = LV_TIMEOUT) {
  await page.waitForFunction(() => {
    const roots = document.querySelectorAll('[data-phx-session]')
    if (![...roots].every(root => root.classList.contains('phx-connected'))) return false
    return !document.querySelector('.phx-change-loading, .phx-click-loading, .phx-submit-loading')
  }, null, { timeout, polling: 100 })
  await page.evaluate(() => document.fonts.ready)
}

async function load(page, url) {
  await page.goto(url, { waitUntil: 'load' })
  if (/\/admin\/login/.test(page.url()) && !/\/admin\/login/.test(url)) {
    throw new Error(`redirected to the login page from ${url}: the session is not logged in`)
  }
  if (await page.locator('[data-phx-session]').count() === 0) return
  await page.locator('.phx-connected').first().waitFor({ state: 'attached', timeout: LV_TIMEOUT })
  await settle(page)
}

const visible = (page, selector) => page.locator(selector).filter({ visible: true }).first()

async function runAction(page, action, ctx) {
  const v = key => interpolate(localized(action[key], ctx.locale), ctx.vars)
  page.setDefaultTimeout(action.timeout || LV_TIMEOUT)
  if ('click' in action) await visible(page, v('click')).click()
  else if ('hover' in action) await visible(page, v('hover')).hover()
  else if ('fill' in action) await visible(page, v('fill')).fill(String(v('value') ?? ''))
  else if ('select' in action) await visible(page, v('select')).selectOption(String(v('value')))
  else if ('press' in action) {
    if (action.on) await visible(page, v('on')).press(v('press'))
    else await page.keyboard.press(v('press'))
  } else if ('waitFor' in action) {
    const state = action.state || 'visible'
    const locator = state === 'visible' ? visible(page, v('waitFor')) : page.locator(v('waitFor')).first()
    await locator.waitFor({ state })
  } else if ('wait' in action) await page.waitForTimeout(Number(action.wait))
  else if ('scroll' in action) {
    const target = v('scroll')
    if (target === 'bottom') await page.evaluate(() => window.scrollTo(0, document.documentElement.scrollHeight))
    else if (target === 'top') await page.evaluate(() => window.scrollTo(0, 0))
    else if (typeof target === 'object') await page.evaluate(({ x = 0, y = 0 }) => window.scrollTo(x, y), target)
    else await visible(page, target).scrollIntoViewIfNeeded()
  } else if ('goto' in action) await load(page, v('goto'))
  else if ('evaluate' in action) await page.evaluate(v('evaluate'))
  else throw new Error(`Unknown action ${JSON.stringify(action)}`)
  if (!('wait' in action)) await settle(page)
}

async function request(context, method, url, data) {
  const response = await context.request.fetch(url, { method, ...(data === undefined ? {} : { data }) })
  const body = await response.text()
  if (!response.ok()) throw new Error(`${method} ${url}: HTTP ${response.status()} ${body.slice(0, 300)}`)
  try { return JSON.parse(body) } catch { return body }
}

async function runSetup(context, setup, ctx) {
  for (const step of setup) {
    let result
    if (step.fixture) result = await request(context, 'POST', `/e2e/setup_fixtures/${step.fixture}`)
    else if (step.post) result = await request(context, 'POST', interpolate(step.post, ctx.vars), step.data)
    else if (step.factory) {
      const attributes = JSON.parse(interpolate(JSON.stringify(step.attributes || {}), ctx.vars))
      result = await request(context, 'POST', '/__e2e/db/factory', {
        schema: step.factory, attributes, creator_id: step.creator_id ?? 1, fields: step.fields || ['id'],
        ...(step.oban_testing ? { oban_testing: step.oban_testing } : {}),
      })
    } else throw new Error(`Unknown setup step ${JSON.stringify(step)}`)
    if (step.as) ctx.vars[step.as] = result
  }
}

async function login(context, page, ctx, cfg) {
  if (ctx.locale === 'no' && cfg.password === undefined) {
    if (!cfg.sandbox) throw new Error('switching the admin to Norwegian needs the sandbox (drop --no-sandbox)')
    await request(context, 'POST', '/e2e/setup_fixtures/admin-language-no')
  } else if (ctx.locale === 'no') {
    throw new Error('the no locale switches the E2E admin; for another user, set its language in the profile and use --locales en')
  } else if (ctx.locale !== 'en') {
    throw new Error(`unsupported locale ${ctx.locale} (use en or no)`)
  } else if (cfg.password === undefined) {
    await request(context, 'POST', `/e2e/login/${encodeURIComponent(cfg.email)}`)
  } else {
    await page.goto('/admin/login')
    await page.locator('input[type="email"]').fill(cfg.email)
    await page.locator('input[type="password"]').fill(cfg.password)
    await page.locator('input[type="password"]').press('Enter')
    await page.waitForURL(url => !/\/admin\/login/.test(url.pathname), { timeout: LV_TIMEOUT })
  }
}

// Runs in the page: unsticks sticky elements and, for an element shot, hides
// fixed ones, by inline !important styles. The next shot reloads the page.
function neutraliseOverlays(target, { keep, element }) {
  const keepSelector = keep.join(', ')
  for (const el of document.querySelectorAll('body *')) {
    const { position } = getComputedStyle(el)
    if (position !== 'sticky' && position !== 'fixed') continue
    if (el.closest(keepSelector) || el.contains(target)) continue
    if (position === 'sticky') {
      el.style.setProperty('position', 'relative', 'important')
      el.style.setProperty('inset', 'auto', 'important')
    } else if (element && !target.contains(el)) {
      el.style.setProperty('visibility', 'hidden', 'important')
    }
  }
}

async function capture(page, shot, file, cfg) {
  const options = { path: file, animations: 'disabled', caret: 'hide' }
  if (shot.clip) return page.screenshot({ ...options, clip: shot.clip })
  const fullPage = shot.fullPage ?? cfg.fullPage
  const target = shot.element ? visible(page, interpolate(shot.element, cfg.vars)) : null
  const unstick = cfg.unstickFromCli ?? shot.unstick ?? cfg.unstick
  if (unstick && (target || fullPage)) {
    const keep = [...KEEP_OVERLAYS, ...cfg.keep, ...(shot.keep || [])].map(sel => interpolate(sel, cfg.vars))
    const neutralise = target ? target : page.locator('body')
    await neutralise.evaluate(neutraliseOverlays, { keep, element: !!target })
    // A full page captured while scrolled repeats the fixed elements at the
    // scroll position over a black band, so it starts from the top. Then
    // one frame for the new layout to paint.
    await page.evaluate(top => new Promise(resolve => {
      if (top) window.scrollTo(0, 0)
      requestAnimationFrame(() => requestAnimationFrame(resolve))
    }), !target)
  }
  if (target) return target.screenshot(options)
  return page.screenshot({ ...options, fullPage })
}

async function main() {
  const opts = parseArgs(process.argv.slice(2))
  if (opts.help) {
    const source = readFileSync(fileURLToPath(import.meta.url), 'utf8').split('\n')
    console.log(source.slice(1, source.findIndex(line => line.startsWith('import'))).map(l => l.replace(/^\/\/ ?/, '')).join('\n'))
    return
  }
  const spec = await loadSpec(opts.spec)
  let shots = [...(spec.shots || []), ...opts.shots]
  if (opts.only) shots = shots.filter(shot => opts.only.includes(shot.name))
  if (!shots.length) fail('Nothing to shoot: pass --shot <name>=<path> or --spec <file>. Run with --help.')
  for (const shot of shots) if (!shot.name || !shot.path) fail(`Every shot needs a name and a path: ${JSON.stringify(shot)}`)

  const instance = opts.instance || spec.instance || process.env.BRANDO_E2E_INSTANCE
  const base = resolveBase(opts, spec)
  const label = opts.label || spec.label || 'after'
  const outDir = path.resolve(opts.out || spec.out || path.join(playwrightDir, 'test-results/shots'), label)
  const widths = opts.widths || spec.widths || [1440, 390]
  const locales = opts.locales || spec.locales || ['en']
  const cfg = {
    email: opts.email || spec.login?.email || DEFAULT_EMAIL,
    password: opts.password ?? spec.login?.password,
    sandbox: opts.sandbox ?? spec.sandbox ?? true,
    fullPage: spec.fullPage ?? true,
    hideToasts: opts.hideToasts ?? spec.hideToasts ?? false,
    unstick: spec.unstick ?? true,
    unstickFromCli: opts.unstick,
    keep: spec.keep || [],
  }
  if (cfg.email !== DEFAULT_EMAIL && cfg.password === undefined) cfg.password = DEFAULT_PASSWORD
  if (widths.some(w => !Number.isInteger(w) || w < 200)) fail(`Bad widths: ${widths.join(',')}`)

  await ensureServer(base, instance)
  mkdirSync(outDir, { recursive: true })

  let chromium
  try {
    ({ chromium } = require('@playwright/test'))
  } catch {
    fail(`Playwright is not installed in ${playwrightDir}: run pnpm install there.`)
  }
  const browser = await chromium.launch({ args: ['--font-render-hinting=none'] })
  console.log(`Shooting ${shots.length} shot(s) × ${locales.length} locale(s) × ${widths.length} width(s) from ${base} into ${outDir}`)

  const failures = []
  const written = []
  try {
    for (const locale of locales) {
      for (const width of widths) {
        const todo = shots.filter(shot => (shot.locales || locales).includes(locale) && (shot.widths || widths).includes(width))
        if (!todo.length) continue
        const height = spec.height && width >= 768 ? spec.height : width < 768 ? 844 : 1000

        let userAgent
        if (cfg.sandbox) {
          const response = await fetch(`${base}/sandbox`, { method: 'POST' }).catch(error => ({ ok: false, statusText: error.message }))
          userAgent = response.ok ? await response.text() : ''
          if (!userAgent.startsWith('BeamMetadata')) {
            await browser.close()
            fail(`${base} has no E2E SQL sandbox (${response.status || response.statusText}). Point --base/--instance at an E2E server, or pass --no-sandbox.`)
          }
        }

        const context = await browser.newContext({ baseURL: base, viewport: { width, height }, ...(userAgent ? { userAgent } : {}) })
        if (cfg.hideToasts) await context.addInitScript(() => {
          const style = document.createElement('style')
          style.textContent = '.toast-stack { display: none !important; }'
          document.addEventListener('DOMContentLoaded', () => document.head.appendChild(style))
        })
        context.setDefaultTimeout(LV_TIMEOUT)
        const page = await context.newPage()
        const ctx = { locale, width, vars: {} }
        try {
          await runSetup(context, spec.setup || [], ctx)
          await login(context, page, ctx, cfg)
          for (const shot of todo) {
            const file = path.join(outDir, `${shot.name}-${locale}-${width}.png`)
            try {
              await load(page, interpolate(shot.path, ctx.vars))
              for (const action of shot.actions || []) await runAction(page, action, ctx)
              await page.waitForTimeout(shot.settle ?? 300)
              await capture(page, shot, file, { ...cfg, vars: ctx.vars })
              written.push(file)
              console.log(`  ${file}`)
            } catch (error) {
              const debug = file.replace(/\.png$/, '.failed.png')
              await page.screenshot({ path: debug, fullPage: true }).catch(() => {})
              failures.push(`${shot.name} (${locale}, ${width}): ${error.message.split('\n')[0]}  [page: ${debug}]`)
            }
          }
        } catch (error) {
          failures.push(`setup/login (${locale}, ${width}): ${error.message.split('\n')[0]}`)
        } finally {
          await context.close()
          if (userAgent) await fetch(`${base}/sandbox`, { method: 'DELETE', headers: { 'user-agent': userAgent } }).catch(() => {})
        }
      }
    }
  } finally {
    await browser.close()
  }

  console.log(`${written.length} screenshot(s) written to ${outDir}`)
  if (failures.length) {
    console.error(`\n${failures.length} failed:`)
    for (const failure of failures) console.error(`  ${failure}`)
    process.exit(1)
  }
}

await main()
