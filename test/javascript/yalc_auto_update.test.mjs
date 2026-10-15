import { test } from 'node:test'
import assert from 'node:assert/strict'
import { mkdtemp, writeFile } from 'node:fs/promises'
import { tmpdir } from 'node:os'
import path from 'node:path'

import { installedFromYalc } from '../../assets/vite/yalcAutoUpdate.mjs'

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
