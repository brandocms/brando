/**
 * Brando.ProposalPreview — the page preview of a content proposal.
 *
 * The iframe renders the site's own template (`/__livepreview?key=…`). Blocks
 * there are delimited by `[+:B<uid>]` … `[-:B<uid>]` comments; this hook finds
 * the blocks the proposal changes and draws a removable outline over them,
 * outside the page's content and layout, then scrolls the first into view.
 *
 * data-highlight   JSON array of block uids to outline
 * data-show        "true" to show the outlines
 * data-viewport    "desktop" renders the page 1280px wide, scaled to fit the
 *                  frame; "mobile" renders it 390px wide
 */
const DESKTOP_WIDTH = 1280
const MOBILE_WIDTH = 390
const OVERLAY_CLASS = 'brando-proposal-highlight'

export default () => ({
  mounted() {
    this.fit()
    this.resizeObserver = new ResizeObserver(() => this.fit())
    this.resizeObserver.observe(this.el.parentElement)
    this.onLoad = () => {
      // A proposal preview is static: show content that scroll-reveal
      // animations would otherwise keep hidden, as the editor's live preview
      // does once it has updated.
      this.el.contentDocument?.documentElement.classList.add('is-updated-live-preview')
      this.highlight(true)
      this.watchLayout()
    }
    this.el.addEventListener('load', this.onLoad)
  },

  updated() {
    this.fit()
    this.highlight(false)
  },

  destroyed() {
    this.el.removeEventListener('load', this.onLoad)
    this.observer?.disconnect()
    this.resizeObserver?.disconnect()
  },

  // The page is laid out at a real viewport width and scaled down to the
  // frame, so a desktop page looks like a desktop page.
  fit() {
    const box = this.el.parentElement
    const width = this.el.dataset.viewport === 'mobile' ? MOBILE_WIDTH : DESKTOP_WIDTH
    const scale = Math.min(1, box.clientWidth / width)
    Object.assign(this.el.style, {
      width: `${width}px`,
      height: `${box.clientHeight / scale}px`,
      transform: `scale(${scale})`,
      transformOrigin: 'top left',
      marginLeft: scale < 1 ? '0' : `${(box.clientWidth - width) / 2}px`,
    })
  },

  // Lazy images and embeds change the page's layout after load; keep the
  // outlines on their blocks.
  watchLayout() {
    const doc = this.el.contentDocument
    const win = doc?.defaultView
    if (!doc?.body || !win?.ResizeObserver) return
    this.observer?.disconnect()
    let frame = null
    this.observer = new win.ResizeObserver(() => {
      if (frame) return
      frame = win.requestAnimationFrame(() => {
        frame = null
        this.highlight(false)
      })
    })
    this.observer.observe(doc.body)
    doc.addEventListener('load', () => this.highlight(false), true)
  },

  highlight(scroll) {
    const doc = this.el.contentDocument
    if (!doc || !doc.body) return
    doc.querySelectorAll(`.${OVERLAY_CLASS}`).forEach(node => node.remove())
    if (this.el.dataset.show !== 'true') return

    let uids = []
    try { uids = JSON.parse(this.el.dataset.highlight || '[]') } catch (_) { uids = [] }

    const rects = uids.map(uid => blockRect(doc, uid)).filter(Boolean)
    const win = doc.defaultView

    rects.forEach(rect => {
      const box = doc.createElement('div')
      box.className = OVERLAY_CLASS
      box.setAttribute('aria-hidden', 'true')
      Object.assign(box.style, {
        position: 'absolute',
        top: `${rect.top + win.scrollY - 6}px`,
        left: `${rect.left + win.scrollX - 6}px`,
        width: `${rect.width + 12}px`,
        height: `${rect.height + 12}px`,
        outline: '3px solid #2f7d5b',
        outlineOffset: '0',
        borderRadius: '6px',
        background: 'rgba(47, 125, 91, 0.06)',
        pointerEvents: 'none',
        zIndex: '2147483647',
      })
      doc.body.appendChild(box)
    })

    if (scroll && rects.length > 0) {
      win.scrollTo({ top: Math.max(rects[0].top + win.scrollY - 80, 0), behavior: 'instant' })
    }
  },
})

// The bounding box of the elements between a block's start and end comments.
function blockRect(doc, uid) {
  const walker = doc.createTreeWalker(doc.body, NodeFilter.SHOW_COMMENT)
  const start = `[+:B<${uid}>]`
  const end = `[-:B<${uid}>]`
  let node
  let open = null

  while ((node = walker.nextNode())) {
    const value = node.nodeValue.trim()
    if (value === start) open = node
    else if (value === end && open) {
      const range = doc.createRange()
      range.setStartAfter(open)
      range.setEndBefore(node)
      const rect = range.getBoundingClientRect()
      return rect.width > 0 || rect.height > 0 ? rect : null
    }
  }

  return null
}
