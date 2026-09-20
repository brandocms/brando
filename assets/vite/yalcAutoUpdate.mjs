import { execFile, execFileSync } from 'node:child_process'
import fs from 'node:fs'
import os from 'node:os'
import path from 'node:path'

const DEFAULT_PACKAGE = '@brandocms/brandojs'
const POLL_MS = 1500

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
 * disagree.
 *
 * Add it to the project's dev config:
 *
 *     import yalcAutoUpdate from '@brandocms/brandojs/vite/yalcAutoUpdate.mjs'
 *
 *     export default defineConfig(({ command }) => ({
 *       optimizeDeps: {
 *         // Vite keys its pre-bundle cache on package.json and the lockfile, so
 *         // a pull never invalidates it. Without this the dev server answers
 *         // from a bundle built before the pull, and the pull changes nothing.
 *         ...(command === 'serve' && { exclude: ['@brandocms/brandojs'] })
 *       },
 *       server: {
 *         // Vite ignores node_modules by default, and that is where the pull
 *         // lands.
 *         watch: { ignored: ['!**\/node_modules/@brandocms/brandojs/**'] }
 *       },
 *       plugins: [yalcAutoUpdate()]
 *     }))
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
      // No lock means this project takes the package from npm rather than from
      // the store, and has nothing to catch up with.
      const lockFile = path.join(server.config.root, 'yalc.lock')
      if (!fs.existsSync(lockFile)) return

      const store = process.env.YALC_STORE_FOLDER || path.join(os.homedir(), '.yalc')
      const storeDir = path.join(store, 'packages', ...packageName.split('/'))
      if (!fs.existsSync(storeDir)) return

      // Read every version the store holds, so a version bump in the published
      // package does not leave this reading a file nothing writes to any more.
      // Re-listed each time because a publish replaces the directory: a name
      // resolved once can be gone by the next read, and mid-publish it can be
      // missing outright, which is not the same thing as being behind.
      const published = () => {
        try {
          return fs.readdirSync(storeDir).flatMap((version) => {
            try {
              return [fs.readFileSync(path.join(storeDir, version, 'yalc.sig'), 'utf8').trim()]
            } catch {
              return []
            }
          })
        } catch {
          return []
        }
      }

      const pulled = () => {
        try {
          return JSON.parse(fs.readFileSync(lockFile, 'utf8')).packages?.[packageName]?.signature
        } catch {
          return null
        }
      }

      const behind = () => {
        const store = published()
        return store.length > 0 && !store.includes(pulled())
      }

      const failed = (error) => {
        const hint = error.code === 'ENOENT' ? 'yalc is not on PATH' : error.message
        server.config.logger.warn(`[yalc] could not update ${packageName}: ${hint}`)
      }

      // Catch up on whatever was published while the server was down. Blocking
      // rather than async: the server is about to start answering requests, and
      // a copy we already know is stale must not be one of the answers.
      if (behind()) {
        try {
          execFileSync('yalc', ['update', packageName], { cwd: server.config.root, stdio: 'pipe' })

          // Said by hanging it off the banner, not off `listening`: Vite clears
          // the screen as it prints that banner, and anything logged before it
          // goes with the rest of the screen.
          const printUrls = server.printUrls.bind(server)
          server.printUrls = () => {
            printUrls()
            server.config.logger.info(`[yalc] pulled ${packageName} on start`)
          }
        } catch (error) {
          failed(error)
        }
      }

      let updating = false

      const pull = () => {
        if (updating || !behind()) return
        updating = true

        execFile('yalc', ['update', packageName], { cwd: server.config.root }, (error) => {
          updating = false
          if (error) return failed(error)

          // Say so: an update that lands silently is indistinguishable from the
          // stale state it just fixed.
          server.config.logger.info(`[yalc] pulled ${packageName}, reloading`)

          // `hot` from Vite 5.1, `ws` for anything older. Projects are on either
          // side of that line, and this plugin ships to all of them.
          ;(server.hot ?? server.ws).send({ type: 'full-reload', path: '*' })
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
