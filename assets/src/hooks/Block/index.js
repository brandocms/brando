import autosize from 'autosize'
import { gsap } from '@brandocms/jupiter'
import { reassertBlockLock } from '../../Presence/blockLocks'

const PRESENCE_THROTTLE_MS = 500
// Focus-settle delay before shipping on focusout — long enough for the
// phx-debounce(300) change flush + validate to land, so the op store holds
// the final keystrokes before the ship reads it.
const SHIP_SETTLE_MS = 400

export default app => ({
  mounted() {
    this.autosizeElements()

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

      // Ship committed content when focus settles after a focusout. Blur
      // alone must sync to other editors — the focus-switch trigger in the
      // form LV only fires when ANOTHER block is focused, which left edits
      // unshipped on plain blur and on ref-to-ref moves inside one block.
      // `still_inside` tells the server whether to also drop presence.
      // Clicking non-focusable UI inside the block (toggles, drag handles,
      // dropdowns) parks focus on <body> — the recent pointer-inside check
      // keeps presence from flapping while the editor is clearly still here.
      this._handleBlockShip = () => {
        clearTimeout(this._shipTimer)
        const uid = this.el.getAttribute('data-block-uid')
        if (!uid) return

        this._shipTimer = setTimeout(() => {
          const active = document.activeElement
          const focusInside = !!(active && active !== document.body && this.el.contains(active))
          const pointerInside = Date.now() - this._lastPointerInside < SHIP_SETTLE_MS * 2
          this.pushEvent('block_blurred', { uid, still_inside: focusInside || pointerInside })
        }, SHIP_SETTLE_MS)
      }
      this.el.addEventListener('focusout', this._handleBlockShip)
    }
  },

  autosizeElements() {
    this.autosized = this.el.querySelectorAll('[data-autosize]')
    Array.from(this.autosized).forEach(el => autosize(el))
  },

  updated() {
    this.autosizeElements()

    // LiveView just reset this element's classes to server truth — restore
    // the lock decoration if another editor holds this block
    const uid = this.el.getAttribute('data-block-uid')
    if (uid) reassertBlockLock(uid)
  },

  destroyed() {
    if (this._handleBlockPresence) {
      this.el.removeEventListener('focusin', this._handleBlockPresence)
      this.el.removeEventListener('pointerdown', this._handleBlockPresence)
    }

    if (this._handleBlockShip) {
      clearTimeout(this._shipTimer)
      this.el.removeEventListener('focusout', this._handleBlockShip)
    }
  }
})
