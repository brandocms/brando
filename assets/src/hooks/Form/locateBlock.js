// "Open in the full editor" from frontend edit mode links to the entry's
// form with `?block=<uid>`. Blocks render after the entry has loaded, so
// wait for the block to appear, then scroll it into view and mark it for a
// moment. The class goes through `hook.js()` so a patch does not strip it.
const WAIT_MS = 20000
const MARK_MS = 2600

export default function locateBlock(hook) {
  const uid = new URLSearchParams(window.location.search).get('block')
  if (!uid) return () => {}

  const selector = `#base-block-${CSS.escape(uid)}`
  let observer = null
  let timer = null

  const done = () => {
    observer?.disconnect()
    observer = null
    clearTimeout(timer)
  }

  const reveal = el => {
    done()
    el.scrollIntoView({ block: 'center', behavior: 'smooth' })
    hook.js().addClass(el, 'is-deep-linked')
    setTimeout(() => el.isConnected && hook.js().removeClass(el, 'is-deep-linked'), MARK_MS)

    // Once found, a reload or a later patch should not jump there again.
    const url = new URL(window.location.href)
    url.searchParams.delete('block')
    window.history.replaceState(window.history.state, '', url)
  }

  const found = document.querySelector(selector)
  if (found) {
    reveal(found)
    return done
  }

  observer = new MutationObserver(() => {
    const el = document.querySelector(selector)
    if (el) reveal(el)
  })
  observer.observe(document.body, { childList: true, subtree: true })
  timer = setTimeout(done, WAIT_MS)

  return done
}
