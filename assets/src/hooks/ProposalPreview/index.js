/**
 * Brando.ProposalPreview — the page preview of a content proposal.
 *
 * The iframe renders the site's own template (`/__livepreview?key=…`) in a
 * sandbox, so this page cannot reach into it. It posts the blocks the
 * proposal changes to the page's script instead (`livepreview_highlight.js`),
 * which outlines them and scrolls the first into view.
 *
 * data-highlight   JSON array of block uids to outline
 * data-show        "true" to show the outlines
 * data-viewport    "desktop" renders the page 1280px wide, scaled to fit the
 *                  frame; "mobile" renders it 390px wide
 */
const DESKTOP_WIDTH = 1280
const MOBILE_WIDTH = 390

export default () => ({
  mounted() {
    this.fit()
    this.resizeObserver = new ResizeObserver(() => this.fit())
    this.resizeObserver.observe(this.el.parentElement)
    this.onLoad = () => this.highlight(true)
    this.el.addEventListener('load', this.onLoad)
    // The page asks to load again (`reloadPage` in livepreview.js); only
    // this frame's page is listened to. Its origin is opaque, so the message
    // is matched by its source, not its origin.
    this.onMessage = event => {
      if (event.source !== this.el.contentWindow) return
      if (event.data?.source === 'brando-live-preview' && event.data.type === 'reload') {
        this.el.src = this.el.getAttribute('src')
      }
    }
    window.addEventListener('message', this.onMessage)
  },

  updated() {
    this.fit()
    this.highlight(false)
  },

  destroyed() {
    this.el.removeEventListener('load', this.onLoad)
    window.removeEventListener('message', this.onMessage)
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

  // The page's origin is opaque, so the message goes to any origin: it holds
  // block uids, and the page checks it comes from this window.
  highlight(scroll) {
    let uids = []
    try { uids = JSON.parse(this.el.dataset.highlight || '[]') } catch (_) { uids = [] }
    this.el.contentWindow?.postMessage(
      { source: 'brando-admin', type: 'highlight', uids, show: this.el.dataset.show === 'true', scroll },
      '*'
    )
  },
})
