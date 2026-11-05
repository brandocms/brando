import { test } from 'node:test'
import assert from 'node:assert/strict'
import { mkdir, mkdtemp, utimes, writeFile } from 'node:fs/promises'
import { tmpdir } from 'node:os'
import path from 'node:path'

import { installedFromYalc, storePublishes } from '../../assets/vite/yalcAutoUpdate.mjs'

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
// publish made after the last pull is an update; an older one, from another
// checkout, would downgrade the installed copy.
const day = 24 * 60 * 60 * 1000

async function store(publishes, pulled) {
  const root = await mkdtemp(path.join(tmpdir(), 'yalc-store-'))
  const storeDir = path.join(root, 'store/packages/@brandocms/brandojs')

  for (const { version, signature, at } of publishes) {
    await mkdir(path.join(storeDir, version), { recursive: true })
    const sig = path.join(storeDir, version, 'yalc.sig')
    await writeFile(sig, `${signature}\n`)
    await utimes(sig, new Date(at), new Date(at))
  }

  const lockFile = path.join(root, 'yalc.lock')
  const lock = { version: 'v1', packages: { '@brandocms/brandojs': { signature: pulled.signature, file: true } } }
  await writeFile(lockFile, JSON.stringify(lock))
  await utimes(lockFile, new Date(pulled.at), new Date(pulled.at))

  return { storeDir, lockFile }
}

const signatures = ({ newer, older }) => ({
  newer: newer.map((publish) => publish.signature),
  older: older.map((publish) => publish.signature),
})

test('a publish made after the last pull is newer', async () => {
  const now = Date.now()
  const { storeDir, lockFile } = await store([{ version: '0.55.0-dev', signature: 'b', at: now }], {
    signature: 'a',
    at: now - day,
  })

  assert.deepEqual(signatures(storePublishes(storeDir, lockFile)), { newer: ['b'], older: [] })
})

test('a publish made before the last pull, from another store, is older and not pulled', async () => {
  const now = Date.now()
  const { storeDir, lockFile } = await store([{ version: '0.55.0-dev', signature: 'old', at: now - 10 * day }], {
    signature: 'setup',
    at: now,
  })

  const { newer, older } = storePublishes(storeDir, lockFile)
  assert.deepEqual(newer, [])
  assert.equal(older[0].signature, 'old')
  assert.equal(older[0].version, '0.55.0-dev')
})

test('the pulled signature is neither, and every version the store holds is read, newest first', async () => {
  const now = Date.now()
  const { storeDir, lockFile } = await store(
    [
      { version: '0.55.0-dev', signature: 'pulled', at: now - 2 * day },
      { version: '0.55.0-beta.0', signature: 'bumped', at: now },
      { version: '0.56.0-dev', signature: 'later', at: now - 1000 },
    ],
    { signature: 'pulled', at: now - day }
  )

  assert.deepEqual(signatures(storePublishes(storeDir, lockFile)), { newer: ['bumped', 'later'], older: [] })
})

test('a store or lock that is missing reads as nothing to pull', async () => {
  const root = await mkdtemp(path.join(tmpdir(), 'yalc-store-'))
  assert.deepEqual(storePublishes(path.join(root, 'none'), path.join(root, 'yalc.lock')), { newer: [], older: [] })
})
