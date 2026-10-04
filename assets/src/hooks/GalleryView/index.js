// The gallery editors' grid/list switch. The view is the admin's own
// preference, remembered per field (or block) in this browser — it is never
// part of the saved content. The server renders its default; a stored choice
// replaces it once the switch mounts.
const read = key => { try { return localStorage.getItem(key) } catch { return null } }
const write = (key, value) => { try { localStorage.setItem(key, value) } catch { /* storage unavailable */ } }

export default () => ({
  mounted() {
    const key = this.el.dataset.storageKey
    const stored = read(key)
    if ((stored === 'grid' || stored === 'list') && stored !== this.el.dataset.view) {
      this.pushEventTo(this.el, 'set_gallery_view', { view: stored })
    }
    this._onClick = event => {
      const button = event.target.closest('[data-gallery-view]')
      if (button && this.el.contains(button)) write(key, button.dataset.galleryView)
    }
    this.el.addEventListener('click', this._onClick)
  },

  destroyed() {
    this.el.removeEventListener('click', this._onClick)
  },
})
