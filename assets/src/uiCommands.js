import { prefersReducedMotion } from './motion'
import surfaceMotion from './surfaceMotion'
import blockMotion from './blockMotion'
import revealRow from './rowMotion'

/**
 * Shared UI commands. Repeated block controls carry only a target id, keeping
 * mount payloads small. One-off controls use BrandoAdmin.JSCommands; both routes
 * share the same motion controller and LiveView's patch-aware visibility.
 * Keep dropdown ops in sync with JSCommands' dropdown builders.
 */

const DROPDOWN_IN = [
  ['ui-menu-motion'],
  ['ui-surface-away'],
  ['ui-surface-rest'],
]

const DROPDOWN_OUT = [
  ['ui-menu-motion'],
  ['ui-surface-rest'],
  ['ui-surface-away'],
]

const toggleDropdownOps = (sel) => [
  ['toggle', { time: 300, ins: DROPDOWN_IN, to: sel, outs: DROPDOWN_OUT }],
]

const hideDropdownOps = (sel) => [
  ['hide', { time: 300, to: sel, transition: DROPDOWN_OUT }],
]

const modalOps = (sel, action) => [
  ['dispatch', {
    event: 'b:ui-surface', to: sel, detail: { kind: 'modal', action },
    blocking: action === 'hide',
  }],
]

/**
 * CSS.escape an id so ids holding `.` or `:` (block uids are generated, but
 * form-derived ids are not always) still produce a valid selector.
 */
const idSelector = (id) => `#${window.CSS && CSS.escape ? CSS.escape(id) : id}`

export default (app) => {
  const moveBlock = blockMotion(app.liveSocket)
  const moveSurface = surfaceMotion(app.liveSocket)
  document.addEventListener('b:ui-surface', event => {
    const { kind, action, done } = event.detail
    // Always release a blocking dispatch, including a detached element or an
    // unexpected animation failure.
    Promise.resolve().then(() => moveSurface(event.target, kind, action)).finally(() => done?.())
  })
  document.addEventListener('b:ui-reveal', event => {
    const { remove, done } = event.detail
    if (!remove) app.liveSocket.js().setAttribute(event.target, 'data-ui-open', 'true')
    const animation = revealRow(event.target, remove)
    if (!animation) { done?.(); return }
    let timer
    let finished = false
    const finish = () => {
      if (finished) return
      finished = true
      clearTimeout(timer)
      done?.()
    }
    animation.finished.then(finish, finish)
    // A background tab must still release a pending LiveView removal.
    if (done) timer = setTimeout(finish, animation.effect.getTiming().duration + 50)
  })
  document.addEventListener('b:select-option', event => {
    const option = event.target
    const select = option.closest('.multiselect[data-select-input]')
    if (!select) return
    const input = document.getElementById(select.dataset.selectInput)
    const origin = document.getElementById(select.dataset.selectOrigin)
    // The visible choice and the submitted value change together. Otherwise
    // Save during the exit/reply delay serializes the previous selection.
    if (origin) origin.value = option.getAttribute('phx-value-origin') || 'local'
    if (input) input.value = option.value
    const label = select.querySelector(':scope > div > .select-label[data-select-preview="true"]')
    // The server uses the same escaping for this label. Custom slots opt out.
    if (label && option.dataset.selectLabel !== undefined) label.innerHTML = option.dataset.selectLabel
    // Use the ordinary form change path, including field sync and LiveView's
    // pending-input protection. Respect inputs that opted out of publishing.
    for (const field of [origin, input]) {
      if (field?.getAttribute('phx-hook') === 'Brando.PublishInput') {
        field.dispatchEvent(new Event('input', { bubbles: true }))
      }
    }
  })
  const exec = (el, ops) => {
    if (!app.liveSocket) return
    app.liveSocket.execJS(el, JSON.stringify(ops))
  }

  // A block menu's Move up and Move down, as it opens: off for the first and
  // the last of the block's siblings, the items of its sortable list. Read
  // from the page rather than sent with every block, which would re-render a
  // block's toolbar whenever a sibling is added or removed. A plain attribute:
  // the menu closes on the next click, and the server ignores a move past an
  // end regardless.
  const markMoveEnds = (menu) => {
    const buttons = menu.querySelectorAll('[data-block-move]')
    if (buttons.length === 0) return
    const list = menu.closest('[phx-hook="Brando.SortableBlocks"]')
    let item = menu
    while (item && item.parentElement !== list) item = item.parentElement
    if (!list || !item) return
    const items = [...list.children].filter(child => child.dataset.uid)
    const index = items.indexOf(item)
    for (const button of buttons) {
      const end = button.dataset.blockMove === 'up' ? index <= 0 : index === items.length - 1
      button.disabled = end
    }
  }

  // Only one dropdown is ever meaningfully open, so tracking the open id beats
  // scanning every `[data-ui-dropdown-toggle]` on the page for each click —
  // there are 115+ of them in a large entry.
  let openDropdownId = null

  const closeOpenDropdown = () => {
    if (!openDropdownId) return
    const el = document.getElementById(openDropdownId)
    if (el) exec(el, hideDropdownOps(idSelector(openDropdownId)))
    openDropdownId = null
  }

  document.addEventListener('click', (e) => {
    const target = e.target

    // `Element.closest` is unavailable on text/document nodes and on SVG in
    // older engines; bail rather than throw inside a global click handler.
    if (!target || typeof target.closest !== 'function') {
      closeOpenDropdown()
      return
    }

    const toggle = target.closest('[data-ui-dropdown-toggle]')

    if (toggle) {
      const id = toggle.getAttribute('data-ui-dropdown-toggle')
      // Replaces the per-trigger `phx-click-away`: any click outside the toggle
      // closes it, including a click on another block's toggle.
      if (openDropdownId && openDropdownId !== id) closeOpenDropdown()

      const el = document.getElementById(id)
      if (el) {
        if (openDropdownId !== id) markMoveEnds(el)
        exec(el, toggleDropdownOps(idSelector(id)))
        openDropdownId = openDropdownId === id ? null : id
      }
    } else {
      closeOpenDropdown()
    }

    const modalShow = target.closest('[data-ui-modal-show]')
    if (modalShow) {
      const id = modalShow.getAttribute('data-ui-modal-show')
      if (document.getElementById(id)) {
        exec(modalShow, modalOps(idSelector(id), 'show'))
      }
      return
    }

    const modalHide = target.closest('[data-ui-modal-hide]')
    if (modalHide) {
      const id = modalHide.getAttribute('data-ui-modal-hide')
      if (document.getElementById(id)) {
        exec(modalHide, modalOps(idSelector(id), 'hide'))
      }
    }
  })

  // Collapsing a block is a checkbox in its form, so the `collapsed` class
  // waited for the validate round trip: instant locally, a visible lag on a
  // real connection. Flip it now; the patch that follows carries the same
  // class. A plain mutation rather than a sticky JS command, so the server's
  // value still wins on later patches (undo, a collaborator's edit).
  document.addEventListener('change', (e) => {
    const input = e.target
    if (!input || typeof input.matches !== 'function') return
    if (!input.matches('.block-action.toggler input[type="checkbox"]')) return
    const block = input.closest('.base-block')
    if (!block) return
    moveBlock(block, input.checked)
  })

  // A patch can remove the open dropdown from the DOM (block deleted, list
  // reordered) and leave the tracked id pointing at nothing.
  window.addEventListener('phx:page-loading-stop', () => {
    if (openDropdownId && !document.getElementById(openDropdownId)) {
      openDropdownId = null
    }
  })

  // Let the destination appear gently without delaying navigation or making
  // fixed drawers descendants of a transformed element.
  let pageAnimation
  let pageFrame
  window.addEventListener('phx:page-loading-stop', ({ detail }) => {
    if (detail?.kind !== 'redirect') return
    pageAnimation?.cancel()
    cancelAnimationFrame(pageFrame)
    // Redirect completion can fire just before the new layout mounts.
    pageFrame = requestAnimationFrame(() => {
      const main = document.getElementById('brando-main')
      if (!main || prefersReducedMotion()) return
      pageAnimation = main.animate([{ opacity: 0.35 }, { opacity: 1 }], {
        duration: 350,
        easing: 'cubic-bezier(0.22, 1, 0.36, 1)',
      })
    })
  })
}
