/**
 * The structured data inspector in an entry's Meta drawer.
 *
 * - Opens the drawer on its Structured data tab when the page is loaded with
 *   `#structured-data` (Content SEO links there), then drops the hash so a
 *   reconnect doesn't toggle the drawer again. The JS that opens it is the
 *   element's `data-open`.
 * - Copies the page's JSON-LD, the exact content of its script tag, from the
 *   hidden `[data-json-ld]` element.
 * - Scrolls a graph wider than the screen to its selected node when it loads.
 */
export default () => ({
  mounted() {
    if (window.location.hash === '#structured-data' && this.el.dataset.open) {
      const { pathname, search } = window.location
      window.history.replaceState(window.history.state, '', pathname + search)
      this.liveSocket.execJS(this.el, this.el.dataset.open)
    }

    this.onClick = event => {
      const button = event.target.closest('[data-copy-json-ld]')
      if (!button || !this.el.contains(button)) return
      const source = this.el.querySelector('[data-json-ld]')
      if (source) this.copy(source.textContent, button)
    }

    this.el.addEventListener('click', this.onClick)
    this.centerGraph()
  },

  updated() {
    this.centerGraph()
  },

  // On a narrow screen the graph scrolls sideways; bring the selected node
  // (the entry's own entity, at first) into view once the graph arrives.
  centerGraph() {
    const graph = this.el.querySelector('.structured-data-graph')
    if (!graph || graph === this.centeredGraph) return
    this.centeredGraph = graph
    if (graph.scrollWidth <= graph.clientWidth) return
    const selected = graph.querySelector('[aria-pressed="true"]')
    if (!selected) return
    const box = selected.getBoundingClientRect()
    const frame = graph.getBoundingClientRect()
    graph.scrollLeft += box.left + box.width / 2 - (frame.left + frame.width / 2)
  },

  destroyed() {
    this.el.removeEventListener('click', this.onClick)
    clearTimeout(this.resetTimer)
  },

  async copy(text, button) {
    try {
      await navigator.clipboard.writeText(text)
    } catch {
      // Without the async clipboard (an insecure origin), copy through a
      // selected textarea.
      const area = document.createElement('textarea')
      area.value = text
      area.setAttribute('readonly', '')
      area.style.position = 'fixed'
      area.style.opacity = '0'
      document.body.appendChild(area)
      area.select()
      document.execCommand('copy')
      area.remove()
    }

    const label = button.querySelector('[data-copy-label]')
    const status = this.el.querySelector('[data-copy-status]')
    const copied = this.el.dataset.copiedLabel || 'Copied'

    if (label) {
      if (!label.dataset.original) label.dataset.original = label.textContent
      label.textContent = copied
    }
    if (status) status.textContent = copied
    button.dataset.copied = 'true'

    clearTimeout(this.resetTimer)
    this.resetTimer = setTimeout(() => {
      if (label?.dataset.original) label.textContent = label.dataset.original
      if (status) status.textContent = ''
      delete button.dataset.copied
    }, 2000)
  },
})
