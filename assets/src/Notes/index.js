// Editors' notes in the entry editor (`Brando.Notes`, the NotesDrawer
// component). The server sends one `b:notes` event whenever the notes
// change; everything the editor shows for them is drawn from it here, so a
// note never re-renders a block:
//
// * a count on each block with open notes: sticky `data-note-count` and
//   `data-note-label` on the block's note button, drawn by CSS (Notes.css);
// * a count on entry field labels with open notes, the same way;
// * the amber highlight of marked text: one stylesheet keyed on the open
//   notes' ids, so the editors' DOM is never touched.
//
// Sticky attributes go through `hook.js()` (DOM.putSticky), so LiveView
// patches keep them. A block that mounts later (the editor loads after the
// entry, inserts, restores) decorates itself through `decorateBlock`.
//
// It also opens the panel, starts a note from a block's button, a field
// label's button (one button, moved to the hovered or focused field) or a
// text selection, and scrolls to a note's place when one is clicked.

const COUNT = 'data-note-count'
const LABEL = 'data-note-label'
const LOCATED = 'is-note-located'
const LOCATED_MS = 2600

export default function notes(hook) {
  const root = hook.el
  let state = { panel: root.dataset.notes || null, enabled: false, blocks: {}, fields: {}, marks: [], labels: {} }
  let decoratedBlocks = new Set()
  let decoratedFields = new Set()
  let fieldButton = null
  let fieldWrapper = null

  const style = document.createElement('style')
  style.dataset.notesHighlights = ''
  document.head.appendChild(style)

  const panel = () => (state.panel ? document.getElementById(state.panel) : null)
  const toggleButton = () => root.querySelector('.form-tool-notes')
  const isOpen = () => !!panel()?.classList.contains('is-open')
  const narrow = () => window.matchMedia('(max-width: 768px)').matches

  // --- Panel

  function open() {
    const el = panel()
    if (!el) return
    const js = hook.js()
    js.addClass(el, 'is-open')
    const toggle = toggleButton()
    if (toggle) js.setAttribute(toggle, 'aria-expanded', 'true')
  }

  function close() {
    const el = panel()
    if (!el) return
    const js = hook.js()
    js.removeClass(el, 'is-open')
    const toggle = toggleButton()
    if (toggle) {
      js.setAttribute(toggle, 'aria-expanded', 'false')
      if (el.contains(document.activeElement)) toggle.focus()
    }
  }

  function compose(anchor) {
    if (!state.enabled || !panel()) return
    open()
    hook.pushEventTo(`#${CSS.escape(state.panel)}`, 'compose', anchor)
  }

  // --- Anchors

  const blockOf = el => el?.closest?.('.block[data-block-uid]:not(.ref_block)')

  function blockLabel(block) {
    const toolbar = block.querySelector('.block-toolbar')
    const name = toolbar?.querySelector('.block-name')
    const text = (name || toolbar?.querySelector('.block-type'))?.textContent || ''
    return text.replace(/<[^>]*>/g, '').replace(/\s+/g, ' ').replace(/\s*\|\s*$/, '').trim()
  }

  // `page[meta][description]` → `meta.description`
  function fieldPath(name) {
    const parts = String(name).match(/[^[\]]+/g) || []
    return parts.slice(1).join('.') || null
  }

  function innerField(el) {
    const variable = el.closest('.variable[data-id]')
    if (variable?.dataset.id) return `var:${variable.dataset.id}`
    const ref = el.closest('.ref-block[data-block-uid]')
    if (ref?.dataset.blockUid) return `ref:${ref.dataset.blockUid}`
    return null
  }

  function labelText(wrapper) {
    const label = wrapper.querySelector(':scope > .label-wrapper label')
    return (label?.querySelector(':scope > span')?.textContent || label?.textContent || '').replace(/\s+/g, ' ').trim()
  }

  function fieldAnchor(wrapper) {
    if (!wrapper) return null
    const text = labelText(wrapper)
    const block = blockOf(wrapper)

    if (block) {
      const path = innerField(wrapper)
      if (!path) return null
      const name = blockLabel(block)
      return { block_uid: block.dataset.blockUid, field_path: path, anchor_label: [name, text].filter(Boolean).join(' · ') }
    }

    const label = wrapper.querySelector(':scope > .label-wrapper [data-field-presence]')
    const path = label && fieldPath(label.getAttribute('data-field-presence'))
    return path ? { field_path: path, anchor_label: text } : null
  }

  function textAnchor(el) {
    const block = blockOf(el)
    if (!block) return null
    const wrapper = el.closest('.field-wrapper')
    const name = blockLabel(block)
    const field = wrapper ? labelText(wrapper) : ''
    return {
      block_uid: block.dataset.blockUid,
      field_path: innerField(el) || undefined,
      anchor_label: [name, field].filter(Boolean).join(' · '),
    }
  }

  // --- Decorations

  function setCount(js, el, info) {
    if (info) {
      if (el.getAttribute(COUNT) !== String(info.count)) js.setAttribute(el, COUNT, String(info.count))
      if (el.getAttribute(LABEL) !== info.label) js.setAttribute(el, LABEL, info.label)
    } else if (el.hasAttribute(COUNT)) {
      js.removeAttribute(el, COUNT)
      js.removeAttribute(el, LABEL)
    }
  }

  function blockButton(uid) {
    return document.getElementById(`block-${uid}`)?.querySelector('[data-block-note]') || null
  }

  function decorateBlockUid(js, uid) {
    const button = blockButton(uid)
    if (button) setCount(js, button, state.blocks[uid])
  }

  function fieldLabels() {
    const form = root.querySelector('form.main-form')
    if (!form) return new Map()
    const labels = new Map()
    form.querySelectorAll('.label-wrapper > [data-field-presence]').forEach(label => {
      const path = fieldPath(label.getAttribute('data-field-presence'))
      if (path) labels.set(path, label.parentElement)
    })
    return labels
  }

  function apply() {
    const js = hook.js()
    const uids = new Set([...decoratedBlocks, ...Object.keys(state.blocks)])
    uids.forEach(uid => decorateBlockUid(js, uid))
    decoratedBlocks = new Set(Object.keys(state.blocks))

    const paths = Object.keys(state.fields)
    if (paths.length || decoratedFields.size) {
      const labels = fieldLabels()
      new Set([...decoratedFields, ...paths]).forEach(path => {
        const el = labels.get(path)
        if (el) setCount(js, el, state.fields[path])
      })
      decoratedFields = new Set(paths)
    }
  }

  function highlight() {
    const selectors = state.marks.map(
      ({ uid, id }) => `#${CSS.escape(`block-${uid}`)} [data-brando-note="${Number(id)}"]`
    )
    style.textContent = selectors.length
      ? `${selectors.join(',\n')} { background: var(--brando-note); box-shadow: inset 0 -2px 0 var(--brando-note-line); border-radius: 2px; }`
      : ''
  }

  // --- Field note button: one element, moved to the field in use

  function ensureFieldButton() {
    if (fieldButton) return fieldButton
    fieldButton = document.createElement('button')
    fieldButton.type = 'button'
    fieldButton.className = 'field-note-add'
    const icon = document.createElement('span')
    icon.setAttribute('data-icon', '')
    icon.className = 'lucide-message-square-plus'
    icon.setAttribute('aria-hidden', 'true')
    fieldButton.append(icon)
    fieldButton.addEventListener('pointerdown', event => event.preventDefault())
    fieldButton.addEventListener('click', event => {
      event.preventDefault()
      event.stopPropagation()
      const anchor = fieldAnchor(fieldWrapper)
      if (anchor) compose(anchor)
    })
    return fieldButton
  }

  function offerFieldButton(target) {
    if (!state.enabled || !target?.closest) return
    const wrapper = target.closest('.field-wrapper')
    if (!wrapper || wrapper === fieldWrapper && fieldButton?.isConnected) return
    if (wrapper.closest('[data-notes-panel], .block-config-carried, .tiptap-editor-shell.expanded')) return
    const labelWrapper = wrapper.querySelector(':scope > .label-wrapper')
    const fieldLabel = labelWrapper?.querySelector(':scope > label')
    if (!fieldLabel || labelWrapper.classList.contains('hidden') || !fieldAnchor(wrapper)) return

    const button = ensureFieldButton()
    // Not "Add note: <field>": tests and assistive tech find a field by its
    // label, and a button named after it would be found too.
    const text = state.labels.add || 'Add note'
    button.setAttribute('aria-label', text)
    button.dataset.tooltip = text
    fieldWrapper = wrapper
    // Beside the label, no taller than its line: offering the button must
    // not move the field under the pointer.
    fieldLabel.after(button)
  }

  // --- Locating a note's place

  function reveal(el, mark) {
    const tab = el.closest('.form-tab[data-tab-name]')
    if (tab && !tab.classList.contains('active')) {
      const button = root.querySelector(`.form-tab-customs button[phx-value-name="${CSS.escape(tab.dataset.tabName)}"]`)
      if (button) {
        button.click()
        setTimeout(() => reveal(el, mark), 150)
        return
      }
    }

    if (narrow()) close()
    ;(mark || el).scrollIntoView({ block: 'center', behavior: 'smooth' })
    const js = hook.js()
    js.addClass(el, LOCATED)
    setTimeout(() => el.isConnected && hook.js().removeClass(el, LOCATED), LOCATED_MS)
  }

  function locate({ blockUid, fieldPath: path, noteId }) {
    if (blockUid) {
      const base = document.getElementById(`base-block-${blockUid}`)
      if (!base) return
      let target = base
      if (path?.startsWith('var:')) {
        const variable = base.querySelector(`.variable[data-id="${CSS.escape(path.slice(4))}"]`)
        target = variable?.closest('.field-wrapper') || variable || base
      } else if (path?.startsWith('ref:')) {
        target = document.getElementById(`base-block-${path.slice(4)}`) || base
      }
      const mark = noteId ? base.querySelector(`[data-brando-note="${CSS.escape(noteId)}"]`) : null
      reveal(target.classList.contains('field-wrapper') ? target : base, mark || (target === base ? null : target))
    } else if (path) {
      const wrapper = fieldLabels().get(path)?.closest('.field-wrapper')
      if (wrapper) reveal(wrapper)
    }
  }

  function flashThreads(uid) {
    const el = panel()
    if (!el) return
    const threads = el.querySelectorAll(`.note-thread[data-note-block="${CSS.escape(uid)}"]`)
    threads.forEach(thread => {
      thread.classList.remove('is-flash')
      void thread.offsetWidth
      thread.classList.add('is-flash')
    })
  }

  // --- Events

  const onToggle = () => (isOpen() ? close() : open())
  const onClose = () => close()
  const onLocate = event => locate(event.target.closest('[data-block-uid], [data-field-path]')?.dataset || {})

  const onClick = event => {
    const button = event.target.closest?.('[data-block-note]')
    if (!button || !root.contains(button)) return
    const block = blockOf(button)
    if (!block) return
    const uid = block.dataset.blockUid
    compose({ block_uid: uid, anchor_label: blockLabel(block) })
    if (state.blocks[uid]) requestAnimationFrame(() => flashThreads(uid))
  }

  const onPointerOver = event => offerFieldButton(event.target)
  const onFocusIn = event => offerFieldButton(event.target)

  const onKeydown = event => {
    if (event.key === 'Escape' && isOpen() && panel()?.contains(event.target) && !event.defaultPrevented) close()
  }

  root.addEventListener('brando:notes:toggle', onToggle)
  root.addEventListener('brando:notes:close', onClose)
  root.addEventListener('brando:notes:locate', onLocate)
  root.addEventListener('click', onClick)
  root.addEventListener('pointerover', onPointerOver)
  root.addEventListener('focusin', onFocusIn)
  root.addEventListener('keydown', onKeydown)

  hook.handleEvent('b:notes', payload => {
    state = { ...state, ...payload }
    apply()
    highlight()
  })

  hook.handleEvent('b:notes:created', ({ id }) => {
    requestAnimationFrame(() => document.querySelector(`.note-thread[data-note-id="${id}"]`)?.scrollIntoView({ block: 'nearest' }))
  })

  return {
    apply,

    // A block that mounts after the notes arrived.
    decorateBlock(el) {
      const uid = el?.dataset?.blockUid
      if (uid && state.blocks[uid]) decorateBlockUid(hook.js(), uid)
    },

    // "Add note" for selected text, in block-owned rich text only: block
    // renders are where the mark is stripped before it reaches the site.
    canAddText(el) {
      return state.enabled && !!panel() && !!el.closest('.blocks-wrapper') && !!blockOf(el)
    },

    composeText(el, extra) {
      const anchor = textAnchor(el)
      if (anchor) compose({ ...anchor, ...extra })
    },

    destroy() {
      root.removeEventListener('brando:notes:toggle', onToggle)
      root.removeEventListener('brando:notes:close', onClose)
      root.removeEventListener('brando:notes:locate', onLocate)
      root.removeEventListener('click', onClick)
      root.removeEventListener('pointerover', onPointerOver)
      root.removeEventListener('focusin', onFocusIn)
      root.removeEventListener('keydown', onKeydown)
      fieldButton?.remove()
      style.remove()
    },
  }
}
