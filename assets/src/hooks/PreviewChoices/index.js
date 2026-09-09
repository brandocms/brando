import { positionDropdown, promoteDropdown } from '../../floatingDropdowns'

// The form owns whether this menu is mounted. Retain its existing close and
// selection events; the hook only positions the currently rendered choices.
export default app => ({
  mounted() {
    const trigger = this.el.previousElementSibling
    promoteDropdown(this.el, this.js())
    this.position = positionDropdown(trigger, this.el, {
      onHidden: () => {
        if (this.closing) return
        this.closing = true
        app.liveSocket.execJS(this.el, this.el.dataset.dropdownClose)
      },
    })
  },
  updated() {
    this.position.update()
  },
  destroyed() {
    this.position.stop()
  },
})
