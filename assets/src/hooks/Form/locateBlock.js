// "Open in the full editor" from frontend edit mode links to the entry's
// form with `?block=<uid>` or `?field=<name>`. Blocks render after the entry
// has loaded, so wait for the target to appear, bring its tab forward, then
// scroll it into view and mark it for a moment. The class goes through
// `hook.js()` so a patch does not strip it.
const WAIT_MS = 20000
const MARK_MS = 2600

export default function locateBlock(hook) {
  const params = new URLSearchParams(window.location.search)
  const uid = params.get('block')
  const field = params.get('field')
  if (!uid && !field) return () => {}

  const find = uid
    ? () => document.querySelector(`#base-block-${CSS.escape(uid)}`)
    : () => {
        const input = hook.el.querySelector(`form.main-form [name$="[${CSS.escape(field)}]"]`)
        return input && (input.closest('.field-wrapper') || input)
      }

  let observer = null
  let timer = null

  const done = () => {
    observer?.disconnect()
    observer = null
    clearTimeout(timer)
  }

  const reveal = el => {
    done()

    // A field on another tab: switch to it first, then look again.
    const tab = el.closest('.form-tab[data-tab-name]')
    if (tab && !tab.classList.contains('active')) {
      const button = hook.el.querySelector(`.form-tab-customs button[phx-value-name="${CSS.escape(tab.dataset.tabName)}"]`)
      if (button) {
        button.click()
        setTimeout(() => reveal(find() || el), 150)
        return
      }
    }

    el.scrollIntoView({ block: 'center', behavior: 'smooth' })
    hook.js().addClass(el, 'is-deep-linked')
    setTimeout(() => el.isConnected && hook.js().removeClass(el, 'is-deep-linked'), MARK_MS)

    // Once found, a reload or a later patch should not jump there again.
    const url = new URL(window.location.href)
    url.searchParams.delete('block')
    url.searchParams.delete('field')
    window.history.replaceState(window.history.state, '', url)
  }

  const found = find()
  if (found) {
    reveal(found)
    return done
  }

  observer = new MutationObserver(() => {
    const el = find()
    if (el) reveal(el)
  })
  observer.observe(document.body, { childList: true, subtree: true })
  timer = setTimeout(done, WAIT_MS)

  return done
}
