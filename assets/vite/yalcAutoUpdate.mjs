import { execFile, execFileSync } from 'node:child_process'
import fs from 'node:fs'
import os from 'node:os'
import path from 'node:path'

const DEFAULT_PACKAGE = '@brandocms/brandojs'
const POLL_MS = 1500

/**
 * Whether the project in `root` takes `packageName` from its .yalc copy:
 * `yalc add` writes `file:.yalc/…`, `yalc add --link` writes `link:.yalc/…`.
 */
export function installedFromYalc(root, packageName = DEFAULT_PACKAGE) {
  try {
    const pkg = JSON.parse(fs.readFileSync(path.join(root, 'package.json'), 'utf8'))
    const spec = pkg.dependencies?.[packageName] ?? pkg.devDependencies?.[packageName] ?? ''
    return /^(file|link):\.yalc\//.test(spec)
  } catch {
    return false
  }
}

/** When `yalc.lock` was last written: the time the project last pulled, or 0. */
export function pulledAt(lockFile) {
  try {
    return fs.statSync(lockFile).mtimeMs
  } catch {
    return 0
  }
}

/**
 * The publishes of `packageName` in a Yalc store (`storeDir` is the package's
 * directory there) whose signature differs from the one `yalc.lock` records,
 * newest first: `newer` were published after the project last pulled, `older`
 * before it. Each is `{ version, signature, at }`, `at` the publish time in
 * milliseconds.
 *
 * Every version the store holds is read, so a version bump in the published
 * package does not leave this reading a file nothing writes to any more.
 * Re-listed each time because a publish replaces the directory: a name
 * resolved once can be gone by the next read, and mid-publish it can be
 * missing outright, which is not the same thing as being behind.
 */
export function storePublishes(storeDir, lockFile, packageName = DEFAULT_PACKAGE) {
  let pulled = null
  try {
    pulled = JSON.parse(fs.readFileSync(lockFile, 'utf8')).packages?.[packageName]?.signature ?? null
  } catch {}

  let versions = []
  try {
    versions = fs.readdirSync(storeDir)
  } catch {}

  const since = pulledAt(lockFile)

  const unpulled = versions
    .flatMap((version) => {
      const sig = path.join(storeDir, version, 'yalc.sig')
      try {
        return [{ version, signature: fs.readFileSync(sig, 'utf8').trim(), at: fs.statSync(sig).mtimeMs }]
      } catch {
        return []
      }
    })
    .filter((publish) => publish.signature !== pulled)
    .sort((a, b) => b.at - a.at)

  return {
    newer: unpulled.filter((publish) => publish.at > since),
    older: unpulled.filter((publish) => publish.at <= since),
  }
}

const when = (ms) => {
  const date = new Date(ms)
  const pad = (n) => String(n).padStart(2, '0')
  return `${date.getFullYear()}-${pad(date.getMonth() + 1)}-${pad(date.getDate())} ${pad(date.getHours())}:${pad(date.getMinutes())}`
}

/**
 * Vite plugin: pull a yalc-linked package as soon as it is published.
 *
 * Developing Brando against a project means publishing brandojs to the yalc
 * store on every save — a `nodemon -x "yalc publish"` in `brando/assets` is the
 * usual arrangement. Publishing only writes to the store, though. The copy in
 * the consuming project moves when someone runs `yalc update` there, and
 * forgetting to is quiet rather than loud: Phoenix reads its templates per
 * request and the project serves the package's CSS from disk, so those go new
 * while the JS stays on whatever was last pulled. The admin then runs one half
 * of one version against the other half of another, which reads as the JS
 * ignoring changes that are plainly in the file.
 *
 * yalc rewrites `yalc.sig` in the store on every publish, and records the
 * signature the project last pulled in its own `yalc.lock`, so those two files
 * say whether the project is behind. Watch the store's copy and pull when they
 * disagree and the store's was published after the project last pulled (the
 * time `yalc.lock` was written).
 *
 * The time matters because the store watched here (`YALC_STORE_FOLDER`, or
 * `~/.yalc`) need not be the one the project pulled from: `mix
 * brando.assets.setup` publishes the Brando dependency to a store of the
 * project's own under `_build`, and `~/.yalc` can hold an earlier publish from
 * another checkout. A signature check alone takes that one as an update and
 * swaps the installed copy for an older one, which a release built from the
 * project's `.yalc` then ships. An older publish is left alone and said once at
 * startup; publishing again brings it in.
 *
 * Add it to the project's dev config:
 *
 *     import yalcAutoUpdate from '@brandocms/brandojs/vite/yalcAutoUpdate.mjs'
 *
 *     export default defineConfig({
 *       plugins: [svelte(), yalcAutoUpdate()]
 *     })
 *
 * The plugin comes from the package it keeps fresh, so a change to the plugin
 * itself needs one manual `yalc update` to arrive. Config is read once at
 * startup anyway, so that restart was already required.
 *
 * @param {string} packageName Package to follow. Defaults to brandojs.
 */
export default function yalcAutoUpdate(packageName = DEFAULT_PACKAGE) {
  return {
    name: 'brando:yalc-auto-update',
    apply: 'serve',

    configureServer(server) {
      // No lock, or a package.json that no longer takes the package from
      // .yalc, means this project installs it from npm and has nothing to
      // catch up with. A lock left behind by an earlier Yalc setup would
      // otherwise swap the npm copy for whatever the store holds.
      const lockFile = path.join(server.config.root, 'yalc.lock')
      if (!fs.existsSync(lockFile) || !installedFromYalc(server.config.root, packageName)) return

      const store = process.env.YALC_STORE_FOLDER || path.join(os.homedir(), '.yalc')
      const storeDir = path.join(store, 'packages', ...packageName.split('/'))
      if (!fs.existsSync(storeDir)) return

      const behind = () => storePublishes(storeDir, lockFile, packageName).newer.length > 0

      // yalc points node_modules at its own copy of the package, which carries
      // no node_modules of its own. npm and yarn hoist the package's
      // dependencies to the project root, so they still resolve from there;
      // pnpm keeps them out of the root, so after a pull nothing the package
      // imports resolves until pnpm links them again. A pure Yalc copy (the one
      // `mix brando.assets.setup` adds) leaves node_modules alone, and pnpm
      // install is what brings the pull into it.
      const root = server.config.root
      const relinks = fs.existsSync(path.join(root, 'pnpm-lock.yaml'))
      const relinkArgs = ['install', '--prefer-offline']

      const failed = (error) => {
        const hint = error.code === 'ENOENT' ? `${error.path} is not on PATH` : error.message
        server.config.logger.warn(`[yalc] could not update ${packageName}: ${hint}`)
      }

      // Said by hanging it off the banner, not off `listening`: Vite clears
      // the screen as it prints that banner, and anything logged before it
      // goes with the rest of the screen.
      const onBanner = (log) => {
        const printUrls = server.printUrls.bind(server)
        server.printUrls = () => {
          printUrls()
          log()
        }
      }

      // Catch up on whatever was published while the server was down. Blocking
      // rather than async: the server is about to start answering requests, and
      // a copy we already know is stale must not be one of the answers.
      const { newer, older } = storePublishes(storeDir, lockFile, packageName)

      if (newer.length > 0) {
        try {
          execFileSync('yalc', ['update', packageName], { cwd: root, stdio: 'pipe' })
          if (relinks) execFileSync('pnpm', relinkArgs, { cwd: root, stdio: 'pipe' })
          const [publish] = newer
          onBanner(() =>
            server.config.logger.info(
              `[yalc] pulled ${packageName} ${publish.version} on start, published to ${store} ${when(publish.at)}`
            )
          )
        } catch (error) {
          failed(error)
        }
      } else if (older.length > 0) {
        // The store watched here can hold a copy older than the installed one
        // (another checkout's publish to ~/.yalc, while `mix
        // brando.assets.setup` pulled from the project's own store). Said, so
        // the publish that was not pulled reads as kept out, not as missed.
        const [publish] = older
        onBanner(() =>
          server.config.logger.warn(
            `[yalc] kept the installed ${packageName}: ${store} holds ${publish.version} published ` +
              `${when(publish.at)}, before this project last pulled (yalc.lock, ${when(pulledAt(lockFile))}). ` +
              'Publish again to pull it.'
          )
        )
      }

      let updating = false

      const pull = () => {
        if (updating || !behind()) return
        updating = true

        const update = (done) =>
          execFile('yalc', ['update', packageName], { cwd: root }, (error) => {
            if (error || !relinks) return done(error)
            execFile('pnpm', relinkArgs, { cwd: root }, done)
          })

        update((error) => {
          updating = false
          if (error) return failed(error)

          // Say so: an update that lands silently is indistinguishable from the
          // stale state it just fixed.
          server.config.logger.info(`[yalc] pulled ${packageName}, re-optimising`)

          // Restarting with the optimizer forced is what makes the pull visible.
          // Vite keys its pre-bundle cache on package.json and the lockfile, so
          // new files in node_modules do not invalidate it and a plain reload
          // re-fetches the same pre-pull bundle.
          //
          // The alternative, `optimizeDeps.exclude`, reloads faster and needs no
          // restart, but it also stops the pre-bundler converting this package's
          // CJS dependencies to ESM -- jupiter's `lodash.defaultsdeep` has no
          // `main`, `module` or `exports` and dies as `does not provide an export
          // named 'default'`. Keeping that list correct across two packages'
          // transitive deps is not a thing a project config should have to do.
          server.restart(true).catch(failed)
        })
      }

      // Polled rather than watched. yalc replaces the whole version directory on
      // publish, so `yalc.sig` is a new file each time and the watcher, pointed
      // at the old one, stops hearing about it after the first publish -- which
      // reads as this working once and then never again. Two small reads every
      // couple of seconds cost nothing and cannot be outsmarted that way.
      const timer = setInterval(pull, POLL_MS)
      timer.unref?.()
      server.httpServer?.once('close', () => clearInterval(timer))
    }
  }
}
