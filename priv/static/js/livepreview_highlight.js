/**
 * Brando live preview: block outlines for a content proposal's page preview.
 *
 * The page is sandboxed, so the admin page that frames it (the
 * `Brando.ProposalPreview` hook) cannot reach into it. It posts the blocks to
 * outline instead:
 *
 *   { source: 'brando-admin', type: 'highlight', uids: [...], show: true, scroll: true }
 *
 * Blocks are delimited by `[+:B<uid>]` … `[-:B<uid>]` comments. The outlines
 * are drawn over them, outside the page's content and layout, and follow
 * them as lazy images and embeds change the layout. `scroll` brings the first
 * into view. The page also shows what scroll-reveal animations would keep
 * hidden, as a live preview does once it has updated.
 */
;(function () {
  const OVERLAY_CLASS = 'brando-proposal-highlight'
  let state = { uids: [], show: false }
  let observer = null

  window.addEventListener('message', event => {
    const data = event.data
    // Only from the admin page framing this one, on the origin it was served from
    if (window.parent === window || event.source !== window.parent || event.origin !== location.origin) return
    if (!data || data.source !== 'brando-admin' || data.type !== 'highlight') return

    document.documentElement.classList.add('is-updated-live-preview')
    state = { uids: Array.isArray(data.uids) ? data.uids.map(String) : [], show: data.show === true }
    highlight(data.scroll === true)
    watchLayout()
  })

  function watchLayout() {
    if (observer || !document.body || !window.ResizeObserver) return
    let frame = null
    observer = new ResizeObserver(() => {
      if (frame) return
      frame = requestAnimationFrame(() => {
        frame = null
        highlight(false)
      })
    })
    observer.observe(document.body)
    document.addEventListener('load', () => highlight(false), true)
  }

  function highlight(scroll) {
    if (!document.body) return
    document.querySelectorAll(`.${OVERLAY_CLASS}`).forEach(node => node.remove())
    if (!state.show) return

    const rects = state.uids.map(blockRect).filter(Boolean)

    rects.forEach(rect => {
      const box = document.createElement('div')
      box.className = OVERLAY_CLASS
      box.setAttribute('aria-hidden', 'true')
      Object.assign(box.style, {
        position: 'absolute',
        top: `${rect.top + window.scrollY - 6}px`,
        left: `${rect.left + window.scrollX - 6}px`,
        width: `${rect.width + 12}px`,
        height: `${rect.height + 12}px`,
        outline: '3px solid #2f7d5b',
        outlineOffset: '0',
        borderRadius: '6px',
        background: 'rgba(47, 125, 91, 0.06)',
        pointerEvents: 'none',
        zIndex: '2147483647',
      })
      document.body.appendChild(box)
    })

    if (scroll && rects.length > 0) {
      window.scrollTo({ top: Math.max(rects[0].top + window.scrollY - 80, 0), behavior: 'instant' })
    }
  }

  // The bounding box of the elements between a block's start and end comments.
  function blockRect(uid) {
    const walker = document.createTreeWalker(document.body, NodeFilter.SHOW_COMMENT)
    const start = `[+:B<${uid}>]`
    const end = `[-:B<${uid}>]`
    let node
    let open = null

    while ((node = walker.nextNode())) {
      const value = node.nodeValue.trim()
      if (value === start) open = node
      else if (value === end && open) {
        const range = document.createRange()
        range.setStartAfter(open)
        range.setEndBefore(node)
        const rect = range.getBoundingClientRect()
        return rect.width > 0 || rect.height > 0 ? rect : null
      }
    }

    return null
  }
})()
