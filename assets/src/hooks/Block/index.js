import autosize from 'autosize'
import { gsap } from '@brandocms/jupiter'

const PRESENCE_THROTTLE_MS = 500

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
      this._handleBlockPresence = () => {
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
  }
})
