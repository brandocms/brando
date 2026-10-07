// Field presence: which field of which block another editor is in.
//
// Two editors can work in one block, so nothing is locked. Only the field
// another editor is in gets their colour and first name; the block's toolbar
// says "Name · Field". Decorations go through LiveView's sticky JS commands
// (`hook.js()` — setAttribute et al funnel into DOM.putSticky), so the patcher
// re-applies them after every morphdom pass. The colour, the outline and the
// labels are pure CSS keyed off the sticky attributes (inline styles and
// injected child nodes are not covered by the sticky mechanism); see
// Block.css.

// Order matches the `data-presence-color-index` palette in Block.css. The
// entry fields' presence avatar still takes the colour as a custom property.
const PRESENCE_COLORS = [
  '77, 144, 254', // blue
  '72, 199, 142', // green
  '245, 166, 35', // orange
  '168, 85, 247', // purple
  '239, 68, 68', // red
  '20, 184, 166', // teal
]

export function getPresenceColorIndex(userId) {
  const els = document.querySelectorAll('.page-presences [data-presence-user-id]')
  const ids = Array.from(els).map(el => el.dataset.presenceUserId)
  const idx = ids.indexOf(String(userId))
  return Math.max(0, idx) % PRESENCE_COLORS.length
}

export function getPresenceColor(userId, alpha = 0.6) {
  return `rgba(${PRESENCE_COLORS[getPresenceColorIndex(userId)]}, ${alpha})`
}

function blockEl(uid) {
  return document.querySelector(`[data-block-uid="${CSS.escape(uid)}"] > .block`)
}

// The block's own toolbar comes before its children's in document order.
function toolbarEl(uid) {
  return blockEl(uid)?.querySelector('.block-toolbar')
}

const FIELD_ATTRS = ['data-field-presence-user', 'data-presence-name', 'data-presence-color-index']
const BLOCK_ATTRS = ['data-block-presence-user', 'data-presence-color-index']
const TOOLBAR_ATTRS = ['data-presence-label', 'data-presence-tag', 'data-presence-color-index', 'data-toolbar-presence-user']

function clear(js, el, attrs, classes = []) {
  if (classes.length) js.removeClass(el, classes)
  attrs.forEach(attr => js.removeAttribute(el, attr))
}

// The field an event happened in, inside a block: a form field (its wrapper
// id) or a ref (its block element id), with a label to show others.
export function fieldOf(blockEl, target) {
  const wrapper = target && target.closest && target.closest('.field-wrapper')
  if (wrapper && blockEl.contains(wrapper) && wrapper.id) {
    const label = wrapper.querySelector('.control-label > span')?.textContent?.trim()
    return { field: wrapper.id, label: label || null }
  }

  const ref = target && target.closest && target.closest('.ref_block')
  if (ref && blockEl.contains(ref) && ref.id) {
    const label =
      ref.querySelector(':scope > .block-toolbar .block-name')?.textContent?.trim() ||
      ref.dataset.blockType ||
      null
    return { field: ref.id, label }
  }

  return { field: null, label: null }
}

export function setFieldPresence(js, { uid, user_id: userId, field, label, name }) {
  // one place per user — clear their previous field and block first
  clearUserPresence(js, userId)

  const colorIndex = String(getPresenceColorIndex(userId))
  const firstName = (name || '').trim().split(/\s+/)[0] || ''

  const block = blockEl(uid)
  if (block) {
    js.setAttribute(block, 'data-block-presence-user', String(userId))
    js.setAttribute(block, 'data-presence-color-index', colorIndex)
  }

  const toolbar = toolbarEl(uid)
  if (toolbar && firstName) {
    js.setAttribute(toolbar, 'data-presence-label', label ? `${firstName} · ${label}` : firstName)
    js.setAttribute(toolbar, 'data-toolbar-presence-user', String(userId))
    js.setAttribute(toolbar, 'data-presence-color-index', colorIndex)
  }

  const fieldEl = field && document.getElementById(field)
  if (fieldEl && block && block.contains(fieldEl)) {
    js.setAttribute(fieldEl, 'data-field-presence-user', String(userId))
    js.setAttribute(fieldEl, 'data-presence-name', firstName)
    js.setAttribute(fieldEl, 'data-presence-color-index', colorIndex)

    // A ref shows the name in its own toolbar: the ref clips anything drawn
    // over its edge.
    const refToolbar = fieldEl.classList.contains('ref_block') && fieldEl.querySelector('.block-toolbar')
    if (refToolbar && firstName) {
      js.setAttribute(refToolbar, 'data-presence-tag', firstName)
      js.setAttribute(refToolbar, 'data-toolbar-presence-user', String(userId))
      js.setAttribute(refToolbar, 'data-presence-color-index', colorIndex)
    }
  }

  return fieldEl || block
}

export function clearFieldPresence(js, uid, userId) {
  const block = blockEl(uid)
  if (block && block.getAttribute('data-block-presence-user') === String(userId)) {
    clearUserPresence(js, userId)
  }
}

export function clearUserPresence(js, userId) {
  const id = String(userId)
  document
    .querySelectorAll(`[data-block-presence-user="${CSS.escape(id)}"]`)
    .forEach(el => clear(js, el, BLOCK_ATTRS))
  document
    .querySelectorAll(`[data-toolbar-presence-user="${CSS.escape(id)}"]`)
    .forEach(el => clear(js, el, TOOLBAR_ATTRS))
  document
    .querySelectorAll(`[data-field-presence-user="${CSS.escape(id)}"]`)
    .forEach(el => clear(js, el, FIELD_ATTRS))
}
