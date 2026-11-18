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
 * red with the module's name on the outline's outer edge, where it covers
 * none of the block and as little of the page as it can (`placeLabel`), and
 * `focus`, a uid to scroll to.
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
  const LABEL_CLASS = 'brando-proposal-highlight-label'
  const OVERLAYS = `.${OVERLAY_CLASS}, .${LABEL_CLASS}`
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
    // At most once a frame, however many images load or resize at once
    const later = () => {
      if (frame) return
      frame = requestAnimationFrame(() => {
        frame = null
        highlight(false)
      })
    }
    observer = new ResizeObserver(later)
    observer.observe(page.body)
    page.addEventListener('load', later, true)
  }

  function highlight(scroll) {
    if (!page.body) return
    page.querySelectorAll(OVERLAYS).forEach(node => node.remove())
    if (!state.show) return

    const found = state.uids.map((uid, index) => ({ uid, rect: blockRect(uid), mark: state.marks && state.marks[index] }))
    const rects = found.filter(item => item.rect)

    // Labels go outside their block, clear of the page's content (`placeLabel`)
    const taken = rects.some(item => item.mark && item.mark.label) ? contentRects() : []

    rects.forEach(({ rect, mark }) => {
      const colors = mark ? MARK_COLORS[mark.kind] || MARK_COLORS.changed : null
      // Kept inside the viewport, so a full-width block shows its sides too.
      // A block wholly beside it (a carousel's hidden slide) gets no outline.
      const left = Math.max(rect.left + window.scrollX - 6, window.scrollX + LINE)
      const right = Math.min(rect.right + window.scrollX + 6, window.scrollX + page.documentElement.clientWidth - LINE)
      if (right <= left) return
      const box = page.createElement('div')
      box.className = OVERLAY_CLASS
      box.setAttribute('aria-hidden', 'true')
      const outline = { top: rect.top + window.scrollY - 6, left, width: Math.max(right - left, 0), height: rect.height + 12 }
      Object.assign(box.style, {
        position: 'absolute',
        top: `${outline.top}px`,
        left: `${outline.left}px`,
        width: `${outline.width}px`,
        height: `${outline.height}px`,
        outline: `${LINE}px solid ${colors ? colors.line : '#2f7d5b'}`,
        outlineOffset: '0',
        borderRadius: '6px',
        background: colors ? 'transparent' : 'rgba(47, 125, 91, 0.06)',
        pointerEvents: 'none',
        zIndex: '2147483647',
      })
      page.body.appendChild(box)

      if (mark && mark.label) {
        const label = page.createElement('div')
        label.className = LABEL_CLASS
        label.setAttribute('aria-hidden', 'true')
        label.textContent = mark.label
        Object.assign(label.style, {
          position: 'absolute',
          top: '0',
          left: '0',
          visibility: 'hidden',
          boxSizing: 'border-box',
          maxWidth: `${Math.max(Math.min(outline.width + 2 * LINE, page.documentElement.clientWidth - 2 * LINE), 48)}px`,
          padding: '3px 8px',
          borderRadius: '3px',
          background: colors.line,
          color: colors.ink,
          font: '600 11px/1.3 system-ui, sans-serif',
          whiteSpace: 'nowrap',
          overflow: 'hidden',
          textOverflow: 'ellipsis',
          pointerEvents: 'none',
          zIndex: '2147483647',
        })
        page.body.appendChild(label)
        const size = label.getBoundingClientRect()
        const spot = placeLabel(outline, size.width, size.height, taken)
        taken.push(spot)
        Object.assign(label.style, { top: `${spot.top}px`, left: `${spot.left}px`, visibility: '' })
      }
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

  const LINE = 3

  // Where a block's label goes, in page coordinates: on the outline's outer
  // edge, above the block or below it, at its left or right end. Never inside
  // the block, so it hides none of the block's content, and never past the
  // page's top, bottom or sides, so the first block on a page keeps its
  // label above it in view. The first spot that covers none of the page's
  // text or media (`taken`, other labels included) wins; when every spot
  // covers some, the one that covers least. Only a block as tall as the whole
  // page, with no room above or below, takes its label inside its top edge.
  function placeLabel(outline, width, height, taken) {
    const doc = page.documentElement
    const minLeft = window.scrollX
    const maxLeft = window.scrollX + doc.clientWidth - width
    const clampLeft = value => Math.max(minLeft, Math.min(value, maxLeft))
    const pageHeight = Math.max(doc.scrollHeight, page.body.scrollHeight)
    const above = outline.top - height
    const below = outline.top + outline.height
    const atLeft = clampLeft(outline.left - LINE)
    const atRight = clampLeft(outline.left + outline.width + LINE - width)

    const spots = [
      { top: above, left: atLeft },
      { top: above, left: atRight },
      { top: below, left: atLeft },
      { top: below, left: atRight },
    ].filter(spot => spot.top >= 0 && spot.top + height <= pageHeight)

    let best = null
    for (const spot of spots) {
      const rect = { top: spot.top, left: spot.left, bottom: spot.top + height, right: spot.left + width }
      const covered = taken.reduce((sum, other) => sum + overlap(rect, other), 0)
      if (covered === 0) return rect
      if (!best || covered < best.covered) best = { rect, covered }
    }

    if (best) return best.rect
    const top = Math.max(outline.top + LINE, 0)
    return { top, left: atLeft, bottom: top + height, right: atLeft + width }
  }

  function overlap(a, b) {
    const width = Math.min(a.right, b.right) - Math.max(a.left, b.left)
    const height = Math.min(a.bottom, b.bottom) - Math.max(a.top, b.top)
    return width > 0 && height > 0 ? width * height : 0
  }

  // The page's text lines and media, in page coordinates
  const MEDIA = 'img, picture, video, iframe, svg, canvas, object, embed, input, select, textarea, button'

  function contentRects() {
    const found = []
    const add = rect => {
      if (rect.width > 0 && rect.height > 0) {
        found.push({
          top: rect.top + window.scrollY,
          left: rect.left + window.scrollX,
          bottom: rect.bottom + window.scrollY,
          right: rect.right + window.scrollX,
        })
      }
    }
    const range = page.createRange()
    const walker = page.createTreeWalker(page.body, NodeFilter.SHOW_TEXT, {
      acceptNode: node =>
        node.nodeValue.trim() && !node.parentElement.closest(`script, style, template, ${OVERLAYS}`)
          ? NodeFilter.FILTER_ACCEPT
          : NodeFilter.FILTER_REJECT,
    })
    let node
    while ((node = walker.nextNode())) {
      range.selectNodeContents(node)
      for (const rect of range.getClientRects()) add(rect)
    }
    page.body.querySelectorAll(MEDIA).forEach(element => {
      if (!element.closest(OVERLAYS) && !element.parentElement.closest('svg')) add(element.getBoundingClientRect())
    })
    return found
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
