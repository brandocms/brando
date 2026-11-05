import { test } from 'node:test'
import assert from 'node:assert/strict'
import { mkdir, mkdtemp, utimes, writeFile } from 'node:fs/promises'
import { tmpdir } from 'node:os'
import path from 'node:path'

import { installedFromYalc, storeState } from '../../assets/vite/yalcAutoUpdate.mjs'

// The plugin follows Yalc publishes only for a project whose package.json
// takes BrandoJS from .yalc. A yalc.lock left behind after switching to npm
// must not swap the npm copy for the store's.
async function project(packageJson) {
  const root = await mkdtemp(path.join(tmpdir(), 'yalc-auto-update-'))
  if (packageJson) await writeFile(path.join(root, 'package.json'), JSON.stringify(packageJson))
  return root
}

test('a file: or link: spec into .yalc follows the store', async () => {
  for (const spec of ['file:.yalc/@brandocms/brandojs', 'link:.yalc/@brandocms/brandojs']) {
    const root = await project({ dependencies: { '@brandocms/brandojs': spec } })
    assert.equal(installedFromYalc(root), true, spec)
  }
})

test('an npm version, a checkout link or no dependency does not', async () => {
  for (const spec of ['0.55.0-beta.0', 'link:../../brando/assets', undefined]) {
    const root = await project({ dependencies: spec ? { '@brandocms/brandojs': spec } : {} })
    assert.equal(installedFromYalc(root), false, String(spec))
  }
})

test('a devDependency counts, and a missing package.json does not', async () => {
  const dev = await project({ devDependencies: { '@brandocms/brandojs': 'file:.yalc/@brandocms/brandojs' } })
  assert.equal(installedFromYalc(dev), true)
  assert.equal(installedFromYalc(await project(null)), false)
})

// The store the dev server watches (~/.yalc) need not be the one the project
// last pulled from (`mix brando.assets.setup` uses one under _build). Only a
// publish made after the project's copy was pulled is an update; an older one,
// from another checkout, would downgrade the installed copy.
const day = 24 * 60 * 60 * 1000
const pkg = '@brandocms/brandojs'

async function stamp(file, contents, at) {
  await mkdir(path.dirname(file), { recursive: true })
  await writeFile(file, contents)
  await utimes(file, new Date(at), new Date(at))
}

// `publishes` in the store; `installed`, the project's .yalc copy; `lock`, the
// signature and time yalc.lock records (written by any package's update).
async function backend({ publishes, installed, lock }) {
  const dir = await mkdtemp(path.join(tmpdir(), 'yalc-store-'))
  const storeDir = path.join(dir, 'store/packages', pkg)
  const root = path.join(dir, 'backend')
  await mkdir(root, { recursive: true })

  for (const { version, signature, at } of publishes) {
    await stamp(path.join(storeDir, version, 'yalc.sig'), `${signature}\n`, at)
  }

  if (installed) await stamp(path.join(root, '.yalc', pkg, 'yalc.sig'), installed.signature, installed.at)

  if (lock) {
    const contents = JSON.stringify({ version: 'v1', packages: { [pkg]: { signature: lock.signature, pure: true } } })
    await stamp(path.join(root, 'yalc.lock'), contents, lock.at)
  }

  return { storeDir, root }
}

const now = Date.now()

test('a publish made after the copy was pulled is newer', async () => {
  const { storeDir, root } = await backend({
    publishes: [{ version: '0.55.0-dev', signature: 'b', at: now }],
    installed: { signature: 'a', at: now - day },
  })

  const state = storeState(storeDir, root)
  assert.equal(state.status, 'newer')
  assert.equal(state.publish.signature, 'b')
})

test('a publish made before the copy was pulled, from another store, is older and not pulled', async () => {
  const { storeDir, root } = await backend({
    publishes: [{ version: '0.55.0-dev', signature: 'old', at: now - 10 * day }],
    installed: { signature: 'setup', at: now },
  })

  const state = storeState(storeDir, root)
  assert.equal(state.status, 'older')
  assert.equal(state.publish.version, '0.55.0-dev')
  assert.equal(state.pulled, now)
})

test('the copy installed is current, and an old version left in the store is no news', async () => {
  const { storeDir, root } = await backend({
    publishes: [
      { version: '0.54.3', signature: 'months-old', at: now - 90 * day },
      { version: '0.55.0-dev', signature: 'pulled', at: now - 2 * day },
    ],
    installed: { signature: 'pulled', at: now - day },
  })

  assert.deepEqual(storeState(storeDir, root), { status: 'current' })
})

test('every version is read: a bumped version published later is newer', async () => {
  const { storeDir, root } = await backend({
    publishes: [
      { version: '0.55.0-dev', signature: 'pulled', at: now - 2 * day },
      { version: '0.55.0-beta.0', signature: 'bumped', at: now },
    ],
    installed: { signature: 'pulled', at: now - day },
  })

  const state = storeState(storeDir, root)
  assert.equal(state.status, 'newer')
  assert.equal(state.publish.version, '0.55.0-beta.0')
})

test('another package updating yalc.lock after a publish does not hide it', async () => {
  // Pulled A; B published while the server was down; then `yalc update other`.
  const { storeDir, root } = await backend({
    publishes: [{ version: '0.55.0-dev', signature: 'B', at: now - day }],
    installed: { signature: 'A', at: now - 2 * day },
    lock: { signature: 'A', at: now },
  })

  assert.equal(storeState(storeDir, root).status, 'newer')
})

test('a publish landing while a pull copies is newer than the copy that pull made', async () => {
  // The pull copied yalc.sig, then the next publish wrote the store's.
  const { storeDir, root } = await backend({
    publishes: [{ version: '0.55.0-dev', signature: 'second', at: now }],
    installed: { signature: 'first', at: now - 500 },
    lock: { signature: 'first', at: now + 500 },
  })

  assert.equal(storeState(storeDir, root).status, 'newer')
})

test("without a copied yalc.sig, the lock's signature counts; an empty store is current", async () => {
  const { storeDir, root } = await backend({
    publishes: [{ version: '0.55.0-dev', signature: 'a', at: now }],
    lock: { signature: 'a', at: now },
  })

  assert.deepEqual(storeState(storeDir, root), { status: 'current' })

  const empty = await mkdtemp(path.join(tmpdir(), 'yalc-store-'))
  assert.deepEqual(storeState(path.join(empty, 'none'), empty), { status: 'current' })
})
