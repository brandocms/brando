/**
 * BlockField hook — handles block form recovery after disconnect/reconnect.
 *
 * On disconnect, captures all block form data from the DOM and stores it
 * in sessionStorage. On reconnect, compares stored UIDs against current
 * DOM and sends any missing blocks to the server for reconstruction.
 */

const STORAGE_PREFIX = 'brando:block-recovery:'

/**
 * Convert a form's FormData into a nested params object matching
 * Phoenix's parameter parsing convention.
 *
 * "entry_block[block][uid]" = "abc" → { entry_block: { block: { uid: "abc" } } }
 */
function formDataToParams(form) {
  const result = {}
  new FormData(form).forEach((value, key) => {
    const parts = key.replace(/\]/g, '').split('[')
    let current = result
    for (let i = 0; i < parts.length - 1; i++) {
      if (!(parts[i] in current)) {
        current[parts[i]] = {}
      }
      current = current[parts[i]]
    }
    current[parts[parts.length - 1]] = value
  })
  return result
}

export default app => ({
  mounted() {
    this.maybeRecoverBlocks()
  },

  reconnected() {
    this.maybeRecoverBlocks()
  },

  disconnected() {
    this.captureBlockForms()
  },

  /**
   * Capture all block form data and store in sessionStorage.
   */
  captureBlockForms() {
    const sortableEl = this.el.querySelector('[data-sortable-id="sortable-blocks"]')
    if (!sortableEl) return

    // Get root block UIDs in DOM order
    const rootItems = sortableEl.querySelectorAll(':scope > .entry-block[data-uid]')
    const rootUids = Array.from(rootItems).map(el => el.dataset.uid)

    if (rootUids.length === 0) return

    // Capture all block forms (root + children) within this block field
    const forms = {}
    sortableEl.querySelectorAll('form').forEach(form => {
      if (!form.id) return
      forms[form.id] = formDataToParams(form)
    })

    sessionStorage.setItem(
      STORAGE_PREFIX + this.el.id,
      JSON.stringify({ rootUids, forms })
    )
  },

  /**
   * Check sessionStorage for recovery data and send missing blocks to server.
   *
   * Compares stored root UIDs against what's currently rendered. If all blocks
   * are present, does nothing. If some are missing (unsaved blocks lost when
   * the LV process died), sends only the missing ones for reconstruction.
   */
  maybeRecoverBlocks() {
    const key = STORAGE_PREFIX + this.el.id
    const stored = sessionStorage.getItem(key)
    if (!stored) return

    sessionStorage.removeItem(key)

    const sortableEl = this.el.querySelector('[data-sortable-id="sortable-blocks"]')
    if (!sortableEl) return

    try {
      const data = JSON.parse(stored)
      const currentBlocks = sortableEl.querySelectorAll(':scope > .entry-block[data-uid]')
      const currentUids = new Set(Array.from(currentBlocks).map(el => el.dataset.uid))

      // Find UIDs that were in the old DOM but aren't in the new render
      const missingUids = data.rootUids.filter(uid => !currentUids.has(uid))

      if (missingUids.length === 0) return

      // Filter forms to only include missing blocks' data
      const missingForms = {}
      for (const [formId, formData] of Object.entries(data.forms)) {
        // Include root block forms for missing UIDs
        for (const uid of missingUids) {
          if (formId === `entry_block_form-${uid}`) {
            missingForms[formId] = formData
          }
        }
      }

      // Send the full root UID order (for correct positioning) plus missing data
      this.pushEventTo(this.el, 'recover_blocks', {
        rootUids: data.rootUids,
        currentUids: Array.from(currentUids),
        missingUids,
        forms: missingForms
      })
    } catch (e) {
      console.warn('Block recovery failed:', e)
    }
  }
})
