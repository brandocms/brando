// The listing row an entry is opening from (approved October 2026).
//
// LiveView keeps the listing on screen until the entry form's first render
// arrives, which for an entry with many blocks takes a moment. Meanwhile the
// row that was clicked is tinted, says "Opening" after the title (rendered
// hidden by `update_link`) and draws a 2px line along its foot (rendered
// hidden by `Row`): `is-opening` in `Opening.css`.
//
// LiveView marks the link it navigates from with `phx-click-loading` before it
// dispatches `phx:page-loading-start`, so the row is the one around that link.
// The class goes on through LiveView's JS commands, which are sticky: a patch
// of the listing while it waits (presence, a status change) keeps it. It
// comes off when the navigation ends: normally the listing is gone by then,
// but a navigation that fails or is replaced (the back button, a redirect)
// can leave it on screen, and so can the browser's back-forward cache.
//
// Dependency-free, so `test/javascript/opening_row.test.mjs` can load it.

const ROW = '.child-row, .list-row'

export const openingRow = (to, doc = document) => {
  const link = Array.from(doc.querySelectorAll('a.phx-click-loading[data-phx-link="redirect"]')).find(
    (a) => a.href === to
  )
  return link ? link.closest(ROW) : null
}

export default function installOpeningRows(liveSocket, win = window, doc = document) {
  const marked = new Set()

  const clear = () => {
    marked.forEach((row) => {
      if (row.isConnected) {
        liveSocket.js().removeClass(row, 'is-opening')
        liveSocket.js().removeAttribute(row, 'aria-busy')
      }
    })
    marked.clear()
  }

  win.addEventListener('phx:page-loading-start', ({ detail }) => {
    if (!detail || detail.kind !== 'redirect') return
    clear()
    const row = openingRow(detail.to, doc)
    if (!row) return
    liveSocket.js().addClass(row, 'is-opening')
    liveSocket.js().setAttribute(row, 'aria-busy', 'true')
    marked.add(row)
  })

  // `element` is an event's own loading state, not a navigation
  win.addEventListener('phx:page-loading-stop', ({ detail }) => {
    if (!detail || detail.kind !== 'element') clear()
  })
  win.addEventListener('pageshow', (e) => {
    if (e.persisted) clear()
  })

  return { clear }
}
