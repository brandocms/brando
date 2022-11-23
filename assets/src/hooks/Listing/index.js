import { Dom } from '@brandocms/jupiter'

export default app => ({
  mounted() {
    this.entryLinks = Dom.all(this.el, '.entry-link')
    Array.from(this.entryLinks).forEach(l =>
      l.addEventListener('click', this.anchorListener, false)
    )
  },

  destroyed() {
    Array.from(this.entryLinks).forEach(l =>
      l.removeEventListener('click', this.anchorListener, false)
    )
  },

  anchorListener(ev) {
    // ev.stopPropagation()
  }
})
