// The multi-select dialog's option rows are checkbox buttons, toggled with
// the pointer, Space or Enter. Patching the selection that the toggle sends
// back takes the focus off the row (to <body>), so the next key would go
// nowhere. When a row loses the focus to nothing, it takes it back once the
// patch is done, provided nothing else has taken it in the meantime.
export default () => ({
  mounted() {
    this.onFocusOut = event => {
      const row = event.target.closest?.('.multiselect-option')
      if (!row || event.relatedTarget) return

      requestAnimationFrame(() => {
        const active = document.activeElement
        if (row.isConnected && (!active || active === document.body)) row.focus({ preventScroll: true })
      })
    }

    this.el.addEventListener('focusout', this.onFocusOut)
  },

  destroyed() {
    this.el.removeEventListener('focusout', this.onFocusOut)
  },
})
