/**
 * The site and environment switcher (`<details id="tenant-switcher">`).
 *
 * A long site list scrolls inside its own rows; when the sheet opens, the
 * current row is brought into view there. Only the list's own scrollTop
 * moves: `scrollIntoView` would also scroll the navigation and the page.
 */
function revealCurrent(details) {
  details.querySelectorAll('.tenant-switcher__rows').forEach(list => {
    const current = list.querySelector('[aria-current="true"]')
    if (!current || list.scrollHeight <= list.clientHeight) return

    const listBox = list.getBoundingClientRect()
    const rowBox = current.getBoundingClientRect()

    if (rowBox.top < listBox.top) {
      list.scrollTop -= listBox.top - rowBox.top
    } else if (rowBox.bottom > listBox.bottom) {
      list.scrollTop += rowBox.bottom - listBox.bottom
    }
  })
}

export default () => ({
  mounted() {
    this.onToggle = () => {
      if (this.el.open) revealCurrent(this.el)
    }
    this.el.addEventListener('toggle', this.onToggle)
  },

  destroyed() {
    this.el.removeEventListener('toggle', this.onToggle)
  }
})
