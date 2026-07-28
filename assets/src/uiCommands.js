/**
 * Delegated UI commands.
 *
 * Serialising a LiveView JS command into every trigger's `phx-click` is a large
 * part of why a 115-block entry costs 6 MB to mount: `show_modal/1` encodes to
 * 749 bytes, `toggle_dropdown/1` to 443, and the block editor emits them once
 * per block — several times over, at every nesting level.
 *
 * These particular triggers only ever vary by the id they act on. So the markup
 * carries just the id in a data attribute and this module rebuilds the command
 * client-side, handing it to LiveView's own executor. Same ops, same
 * transitions, ~40 bytes on the wire instead of ~750.
 *
 * Keep the op arrays below in sync with `BrandoAdmin.Utils.show_modal/2`,
 * `hide_modal/2`, `toggle_dropdown/2` and `hide_dropdown/2` — they are the
 * server-side definition of the same commands, still used by the one-off
 * triggers where inlining costs nothing.
 */

const DROPDOWN_IN = [
  ['transition', 'ease-out', 'duration-300'],
  ['opacity-0', 'y-100'],
  ['opacity-100', 'y-0'],
]

const DROPDOWN_OUT = [
  ['transition', 'ease-in', 'duration-300'],
  ['opacity-100', 'y-0'],
  ['opacity-0', 'y-100'],
]

const toggleDropdownOps = (sel) => [
  ['toggle', { time: 300, ins: DROPDOWN_IN, to: sel, outs: DROPDOWN_OUT }],
]

const hideDropdownOps = (sel) => [
  ['hide', { time: 300, to: sel, transition: DROPDOWN_OUT }],
]

const showModalOps = (sel) => [
  ['show', { display: 'flex', time: 0, to: sel, blocking: false }],
  [
    'show',
    {
      time: 200,
      to: `${sel} .modal-backdrop`,
      transition: [
        ['transition', 'ease-out', 'duration-200'],
        ['opacity-0'],
        ['opacity-100'],
      ],
      blocking: false,
    },
  ],
  [
    'show',
    {
      time: 200,
      to: `${sel} .modal-dialog`,
      transition: [
        ['transition', 'ease-out', 'duration-200'],
        ['opacity-0', 'y-100'],
        ['opacity-100', 'y-0'],
      ],
      blocking: false,
    },
  ],
]

const hideModalOps = (sel) => [
  [
    'hide',
    {
      time: 100,
      to: `${sel} .modal-dialog`,
      transition: [
        ['transition', 'ease-in', 'duration-100'],
        ['opacity-100', 'y-0'],
        ['opacity-0', 'y-100'],
      ],
      blocking: true,
    },
  ],
  [
    'hide',
    {
      time: 100,
      to: `${sel} .modal-backdrop`,
      transition: [
        ['transition', 'ease-in', 'duration-100'],
        ['opacity-100'],
        ['opacity-0'],
      ],
      blocking: false,
    },
  ],
  [
    'hide',
    {
      time: 100,
      to: sel,
      transition: [['transition'], ['opacity-100'], ['opacity-100']],
      blocking: false,
    },
  ],
]

/**
 * CSS.escape an id so ids holding `.` or `:` (block uids are generated, but
 * form-derived ids are not always) still produce a valid selector.
 */
const idSelector = (id) => `#${window.CSS && CSS.escape ? CSS.escape(id) : id}`

export default (app) => {
  const exec = (el, ops) => {
    if (!app.liveSocket) return
    app.liveSocket.execJS(el, JSON.stringify(ops))
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
        exec(modalShow, showModalOps(idSelector(id)))
      }
      return
    }

    const modalHide = target.closest('[data-ui-modal-hide]')
    if (modalHide) {
      const id = modalHide.getAttribute('data-ui-modal-hide')
      if (document.getElementById(id)) {
        exec(modalHide, hideModalOps(idSelector(id)))
      }
    }
  })

  // A patch can remove the open dropdown from the DOM (block deleted, list
  // reordered) and leave the tracked id pointing at nothing.
  window.addEventListener('phx:page-loading-stop', () => {
    if (openDropdownId && !document.getElementById(openDropdownId)) {
      openDropdownId = null
    }
  })
}
