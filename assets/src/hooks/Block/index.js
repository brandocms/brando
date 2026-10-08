import autosize from 'autosize'

const PRESENCE_THROTTLE_MS = 500
// Focus-settle delay before telling the server focus left the block — long
// enough for the phx-debounce(300) change flush + validate to land first.
const SETTLE_MS = 400

export default app => ({
  mounted() {
    this.autosizeElements()
    // A block that mounts after the entry's notes arrived shows its count.
    app.notes?.decorateBlock(this.el)

    // Block-level presence: any interaction inside the block signals focus.
    // Push to the root LiveView (not this.el) because the hook element may be
    // rendered by a child LiveComponent (e.g. VideoBlock) that doesn't handle
    // this event — the form-level hook handles it instead.
    // Listen for both focusin (inputs) and pointerdown (toggles, drag handles).
    //
    // Only fire from root blocks — ref/child blocks (.ref_block) skip since
    // focusin/pointerdown bubble up to the parent block's hook naturally.
    this._isRefBlock = this.el.classList.contains('ref_block')

    if (!this._isRefBlock) {
      this._lastPresencePush = 0
      this._lastPointerInside = 0
      this._handleBlockPresence = () => {
        this._lastPointerInside = Date.now()

        const now = Date.now()
        if (now - this._lastPresencePush < PRESENCE_THROTTLE_MS) return
        this._lastPresencePush = now

        const uid = this.el.getAttribute('data-block-uid')
        if (uid) {
          this.pushEvent('block_focused', { uid })
        }
      }
      this.el.addEventListener('focusin', this._handleBlockPresence)
      this.el.addEventListener('pointerdown', this._handleBlockPresence)

      // Tell the server when focus settles after a focusout: presence clears,
      // and the block takes the other editors' changes it held back while it
      // was in use (their edits reach the edit session as they type).
      // `still_inside` tells the server whether focus only moved inside the
      // block.
      // Clicking non-focusable UI inside the block (toggles, drag handles,
      // dropdowns) parks focus on <body> — the recent pointer-inside check
      // keeps presence from flapping while the editor is clearly still here.
      this._handleBlockSettle = () => {
        clearTimeout(this._settleTimer)
        const uid = this.el.getAttribute('data-block-uid')
        if (!uid) return

        this._settleTimer = setTimeout(() => {
          const active = document.activeElement
          const focusInside = !!(active && active !== document.body && this.el.contains(active))
          const pointerInside = Date.now() - this._lastPointerInside < SETTLE_MS * 2
          this.pushEvent('block_blurred', { uid, still_inside: focusInside || pointerInside })
        }, SETTLE_MS)
      }
      this.el.addEventListener('focusout', this._handleBlockSettle)
    }
  },

  autosizeElements() {
    this.autosized = this.el.querySelectorAll('[data-autosize]')
    Array.from(this.autosized).forEach(el => autosize(el))
  },

  updated() {
    this.autosizeElements()
  },

  destroyed() {
    if (this._handleBlockPresence) {
      this.el.removeEventListener('focusin', this._handleBlockPresence)
      this.el.removeEventListener('pointerdown', this._handleBlockPresence)
    }

    if (this._handleBlockSettle) {
      clearTimeout(this._settleTimer)
      this.el.removeEventListener('focusout', this._handleBlockSettle)
    }
  }
})
