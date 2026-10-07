import { getPresenceColorIndex } from './blockLocks'

// Other editors' unsaved entry fields, marked on each field's presence label
// (`[data-field-presence]`) with sticky attributes, so LiveView patches keep
// them. The label text and the presence colour are CSS, keyed on those
// attributes (see Form.css).
//
// The marks are also kept here: a field can render after the event arrived
// (an entry still loading, a tab opened later), and `apply` marks it then.

const ATTRS = ['data-dirty-by', 'data-dirty-label', 'data-presence-color-index']

export default function dirtyFields(hook) {
  // userId -> { fields, label }
  const byUser = new Map()
  // `apply` runs on every patch of the form; skip the DOM queries while
  // nothing is marked.
  let anyMarked = false

  const marksByField = () => {
    const marks = new Map()
    byUser.forEach(({ fields, label }, userId) => {
      fields.forEach(field => {
        if (!marks.has(field)) marks.set(field, [])
        marks.get(field).push({ userId, label })
      })
    })
    return marks
  }

  const apply = () => {
    if (byUser.size === 0 && !anyMarked) return

    const js = hook.js()
    const marks = marksByField()

    hook.el.querySelectorAll('[data-dirty-by]').forEach(el => {
      if (!marks.has(el.getAttribute('data-field-presence'))) {
        ATTRS.forEach(attr => js.removeAttribute(el, attr))
      }
    })

    marks.forEach((users, field) => {
      const by = users.map(u => u.userId).join(' ')
      const label = users.map(u => u.label).join(' · ')
      const colorIndex = String(getPresenceColorIndex(users[0].userId))

      hook.el
        .querySelectorAll(`[data-field-presence="${CSS.escape(field)}"]`)
        .forEach(el => {
          if (
            el.getAttribute('data-dirty-by') === by &&
            el.getAttribute('data-dirty-label') === label
          ) return

          js.setAttribute(el, 'data-dirty-by', by)
          js.setAttribute(el, 'data-dirty-label', label)
          js.setAttribute(el, 'data-presence-color-index', colorIndex)
        })
    })

    anyMarked = byUser.size > 0
  }

  return {
    set(userId, fields, label) {
      if (fields.length) {
        byUser.set(String(userId), { fields, label })
      } else {
        byUser.delete(String(userId))
      }
      apply()
    },

    clearUser(userId) {
      if (byUser.delete(String(userId))) apply()
    },

    apply,
  }
}
