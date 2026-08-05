/**
 * BlockField hook — handles block form recovery after disconnect/reconnect.
 *
 * On disconnect, captures all block form data from the DOM and stores it
 * in sessionStorage. On reconnect, compares stored UIDs against current
 * DOM and sends any missing blocks to the server for reconstruction.
 */

const STORAGE_PREFIX = 'brando:block-recovery:'

// Snapshots older than this are discarded unread. Recovery is meant to bridge a
// reconnect, which takes seconds; anything surviving an hour is from a session
// the user has long moved on from, and replaying it over a since-changed entry
// is worse than losing it.
const SNAPSHOT_TTL_MS = 60 * 60 * 1000

/**
 * Convert a form's FormData into a nested params object matching
 * Phoenix's parameter parsing convention.
 *
 * "entry_block[block][uid]" = "abc" → { entry_block: { block: { uid: "abc" } } }
 * "entry_block[extensions][]" = "italic" → { entry_block: { extensions: ["italic"] } }
 */
function formDataToParams(form) {
  const result = {}
  new FormData(form).forEach((value, key) => {
    const parts = key.replace(/\]/g, '').split('[')
    let current = result

    for (let i = 0; i < parts.length - 1; i++) {
      const part = parts[i]
      if (part === '') continue

      if (!(part in current)) {
        const nextPart = parts[i + 1]
        // name[] syntax — collect values into an array
        current[part] = (nextPart === '' && i === parts.length - 2) ? [] : {}
      }
      current = current[part]
    }

    const lastPart = parts[parts.length - 1]
    if (lastPart === '' && Array.isArray(current)) {
      current.push(value)
    } else if (lastPart !== '') {
      current[lastPart] = value
    }
  })
  return result
}

export default app => ({
  mounted() {
    // No recovery on fresh mount — only on reconnect after disconnect
  },

  reconnected() {
    this.maybeRecoverBlocks()
  },

  disconnected() {
    this.captureBlockForms()
  },

  /**
   * sessionStorage key for this field's snapshot.
   *
   * The element id is only `"#{singular}_form-…"` — schema-scoped, not
   * entry-scoped — so without the entry id a snapshot taken on entry A would be
   * offered to entry B when navigating between two entries of the same schema
   * without a full page load. Unsaved entries share the `new` bucket; that is
   * strictly narrower than the previous behaviour, where every entry collided.
   */
  storageKey() {
    const entryId = this.el.dataset.entryId || 'new'
    return `${STORAGE_PREFIX}${entryId}:${this.el.id}`
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

    // Parent uid → ordered child uids, for every nesting level. Child wrappers
    // carry `data-parent_uid` (block/render.ex), and querySelectorAll returns
    // document order, so this reconstructs both the tree and each level's
    // sequence — which the server needs, since a block's sequence is derived
    // from its position in the children list, not stored per form.
    const childOrder = {}
    sortableEl.querySelectorAll('[data-parent_uid][data-uid]').forEach(el => {
      const parentUid = el.dataset.parent_uid
      if (!parentUid) return
      if (!childOrder[parentUid]) childOrder[parentUid] = []
      childOrder[parentUid].push(el.dataset.uid)
    })

    sessionStorage.setItem(
      this.storageKey(),
      JSON.stringify({ rootUids, forms, childOrder, savedAt: Date.now() })
    )
  },

  /**
   * Every uid below `rootUid`, at any depth, in the captured tree.
   */
  descendantUids(childOrder, rootUid) {
    const found = []
    const stack = [rootUid]

    while (stack.length > 0) {
      const uid = stack.pop()
      for (const childUid of childOrder[uid] || []) {
        found.push(childUid)
        stack.push(childUid)
      }
    }

    return found
  },

  /**
   * Check sessionStorage for recovery data and send missing blocks to server.
   *
   * Compares stored root UIDs against what's currently rendered. If all blocks
   * are present, does nothing. If some are missing (unsaved blocks lost when
   * the LV process died), sends only the missing ones for reconstruction.
   */
  maybeRecoverBlocks() {
    const key = this.storageKey()
    const stored = sessionStorage.getItem(key)
    if (!stored) return

    const sortableEl = this.el.querySelector('[data-sortable-id="sortable-blocks"]')
    if (!sortableEl) return

    try {
      const data = JSON.parse(stored)

      if (!data.savedAt || Date.now() - data.savedAt > SNAPSHOT_TTL_MS) {
        sessionStorage.removeItem(key)
        return
      }

      const currentBlocks = sortableEl.querySelectorAll(':scope > .entry-block[data-uid]')
      const currentUids = new Set(Array.from(currentBlocks).map(el => el.dataset.uid))

      // Find UIDs that were in the old DOM but aren't in the new render
      const missingUids = data.rootUids.filter(uid => !currentUids.has(uid))

      // Everything survived — the snapshot has no work left in it.
      if (missingUids.length === 0) {
        sessionStorage.removeItem(key)
        return
      }

      // Filter forms down to the missing roots AND everything nested under
      // them. Children were always captured, but only root forms were ever
      // forwarded, so a new unsaved root came back stripped of its children.
      const childOrder = data.childOrder || {}
      const missingForms = {}

      for (const uid of missingUids) {
        const rootFormId = `entry_block_form-${uid}`
        if (data.forms[rootFormId]) missingForms[rootFormId] = data.forms[rootFormId]

        for (const childUid of this.descendantUids(childOrder, uid)) {
          const childFormId = `child_block_form-${childUid}`
          if (data.forms[childFormId]) missingForms[childFormId] = data.forms[childFormId]
        }
      }

      // Send the full root UID order (for correct positioning) plus missing data.
      //
      // The snapshot is dropped in the reply callback, never before the push:
      // this is the only copy of blocks that were never persisted, and a push
      // that throws downstream or never lands would otherwise destroy them.
      // If no reply arrives the snapshot simply survives to the next reconnect,
      // and the TTL above expires it eventually.
      this.pushEventTo(
        this.el,
        'recover_blocks',
        {
          rootUids: data.rootUids,
          currentUids: Array.from(currentUids),
          missingUids,
          forms: missingForms,
          childOrder
        },
        () => sessionStorage.removeItem(key)
      )
    } catch (e) {
      // A snapshot we cannot parse is never going to recover anything.
      sessionStorage.removeItem(key)
      console.warn('Block recovery failed:', e)
    }
  }
})
