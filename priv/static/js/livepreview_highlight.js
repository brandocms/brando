/**
 * Brando live preview: block outlines for a content proposal's page preview.
 *
 * The page is sandboxed, so the admin page that frames it (the
 * `Brando.ProposalPreview` hook) cannot reach into it. It posts the blocks to
 * outline instead:
 *
 *   { source: 'brando-admin', type: 'highlight', uids: [...], show: true, scroll: true }
 *
 * The release review (`Brando.ReleasePreview`) sends `marks` instead of
 * plain uids: `[{uid, kind: 'changed' | 'failed', label}]`, drawn in amber or
 * red with the label above, and `focus`, a uid to scroll to.
 *
 * Blocks are delimited by `[+:B<uid>]` … `[-:B<uid>]` comments. The outlines
 * are drawn over them, outside the page's content and layout, and follow
 * them as lazy images and embeds change the layout. `scroll` brings the first
 * into view. The page also shows what scroll-reveal animations would keep
 * hidden, as a live preview does once it has updated.
 */
;(function () {
  // Read past elements in the content named after their members
  // (`BrandoBlockPatch.shield`, from `block_patch.js`, loaded before this file)
  const page = window.BrandoBlockPatch.shield(document)
  const view = window.BrandoBlockPatch.shield(window)
  const OVERLAY_CLASS = 'brando-proposal-highlight'
  let state = { uids: [], show: false }
  let observer = null

  view.addEventListener('message', event => {
    const data = event.data
    // Only from the admin page framing this one, on the origin it was served from
    if (window.parent === window || event.source !== window.parent || event.origin !== location.origin) return
    if (!data || data.source !== 'brando-admin' || data.type !== 'highlight') return

    page.documentElement.classList.add('is-updated-live-preview')
    const marks = Array.isArray(data.marks) ? data.marks : null
    state = {
      uids: marks ? marks.map(mark => String(mark.uid)) : Array.isArray(data.uids) ? data.uids.map(String) : [],
      marks,
      show: data.show === true,
      focus: data.focus ? String(data.focus) : null,
    }
    highlight(data.scroll === true)
    watchLayout()
  })

  function watchLayout() {
    if (observer || !page.body || !window.ResizeObserver) return
    let frame = null
    observer = new ResizeObserver(() => {
      if (frame) return
      frame = requestAnimationFrame(() => {
        frame = null
        highlight(false)
      })
    })
    observer.observe(page.body)
    page.addEventListener('load', () => highlight(false), true)
  }

  function highlight(scroll) {
    if (!page.body) return
    page.querySelectorAll(`.${OVERLAY_CLASS}`).forEach(node => node.remove())
    if (!state.show) return

    const found = state.uids.map((uid, index) => ({ uid, rect: blockRect(uid), mark: state.marks && state.marks[index] }))
    const rects = found.filter(item => item.rect)

    rects.forEach(({ rect, mark }) => {
      const colors = mark ? MARK_COLORS[mark.kind] || MARK_COLORS.changed : null
      const box = page.createElement('div')
      box.className = OVERLAY_CLASS
      box.setAttribute('aria-hidden', 'true')
      Object.assign(box.style, {
        position: 'absolute',
        top: `${rect.top + window.scrollY - 6}px`,
        left: `${rect.left + window.scrollX - 6}px`,
        width: `${rect.width + 12}px`,
        height: `${rect.height + 12}px`,
        outline: `3px solid ${colors ? colors.line : '#2f7d5b'}`,
        outlineOffset: '0',
        borderRadius: '6px',
        background: colors ? 'transparent' : 'rgba(47, 125, 91, 0.06)',
        pointerEvents: 'none',
        zIndex: '2147483647',
      })

      if (mark && mark.label) {
        const label = page.createElement('div')
        label.textContent = mark.label
        Object.assign(label.style, {
          position: 'absolute',
          top: '-24px',
          left: '-3px',
          padding: '3px 8px',
          borderRadius: '3px',
          background: colors.line,
          color: colors.ink,
          font: '600 11px/1.3 system-ui, sans-serif',
          whiteSpace: 'nowrap',
        })
        box.appendChild(label)
      }

      page.body.appendChild(box)
    })

    const focused = state.focus && rects.find(item => item.uid === state.focus)
    const target = focused || rects[0]

    if ((scroll || focused) && target) {
      window.scrollTo({ top: Math.max(target.rect.top + window.scrollY - 80, 0), behavior: 'instant' })
    }
  }

  // The release review's marks, on the site's own page (not the admin's palette)
  const MARK_COLORS = {
    changed: { line: '#e4b866', ink: '#3c2c0c' },
    failed: { line: '#d9a092', ink: '#4a1d12' },
  }

  // The bounding box of the elements between a block's start and end comments.
  function blockRect(uid) {
    const walker = page.createTreeWalker(page.body, NodeFilter.SHOW_COMMENT)
    const start = `[+:B<${uid}>]`
    const end = `[-:B<${uid}>]`
    let node
    let open = null

    while ((node = walker.nextNode())) {
      const value = node.nodeValue.trim()
      if (value === start) open = node
      else if (value === end && open) {
        const range = page.createRange()
        range.setStartAfter(open)
        range.setEndBefore(node)
        const rect = range.getBoundingClientRect()
        return rect.width > 0 || rect.height > 0 ? rect : null
      }
    }

    return null
  }
})()
