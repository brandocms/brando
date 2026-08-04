/**
 * Drag-to-reorder for transformer entries.
 *
 * This has to live on the stream container itself, not on a wrapper: Sortable
 * only drags *direct* children of the element it is constructed with, and the
 * `phx-update="stream"` div sits between any wrapper and the entries.
 *
 * The whole card is the drag surface — there is no handle. That means two
 * things have to be suppressed:
 *
 * - `forceFallback` keeps Sortable off the native HTML5 drag-and-drop API.
 *   Cards contain <img>, which the browser makes draggable by default, so the
 *   native path hands you an image drag (the copy-to-desktop kind) instead of a
 *   reorder. The CSS side of this is `user-drag: none` on the thumbnails.
 * - `filter` keeps the buttons inside a card clickable. `preventOnFilter: false`
 *   is what lets their click through — Sortable otherwise calls preventDefault
 *   on filtered elements and the delete/edit buttons stop responding.
 *
 * Order is reported as the entries' `data-id` values — the component's own dom
 * ids — because a transformer entry has no database id until the form is saved.
 * The component answers by resetting the stream in the new order, so the DOM
 * Sortable produced and the DOM LiveView believes in converge immediately.
 */
import Sortable from 'sortablejs'

export default (app) => ({
  mounted() {
    // Relations without a sequence have no meaningful order to persist.
    if (this.el.dataset.sortable !== 'true') return

    this.sortable = new Sortable(this.el, {
      animation: 150,
      draggable: '.transformer-entry',
      filter: 'button, a, input, textarea, select, .subform-fields',
      preventOnFilter: false,
      forceFallback: true,
      fallbackTolerance: 4,
      ghostClass: 'is-sorting',
      dragClass: 'drag-item',
      swapThreshold: 0.5,
      onEnd: () => {
        this.pushEventTo(this.el, 'sequenced_subform', { ids: this.sortable.toArray() })
      },
    })
  },

  destroyed() {
    this.sortable?.destroy()
    this.sortable = null
  },
})
