import Sortable from 'sortablejs'

/**
 * Drives the module editor's variable layout canvas.
 *
 * Dragging is the one part of this that genuinely belongs in the browser, so
 * the hook owns SortableJS and nothing else. On every drop it reads the row
 * structure straight out of the DOM and pushes it:
 *
 *   {rows: [["heading"], ["cta_text", "show_arrow"]], surface: "content"}
 *
 * `sequence`, `new_row` and `placement` are all derived from that structure
 * server-side. The hook never holds a model of its own, so a patch landing
 * mid-drag cannot leave the two out of step — the next render is authoritative.
 */

const CHIP_GROUP = 'brando-var-chips'
const ROW_GROUP = 'brando-var-rows'

export default (app) => ({
  mounted() {
    this.target = this.el.dataset.target
    this.build()
  },

  updated() {
    // LiveView owns this subtree, so every patch replaces the lists Sortable
    // was bound to. Rebuild rather than trying to reconcile.
    this.build()
  },

  destroyed() {
    this.teardown()
  },

  teardown() {
    ;(this.sortables || []).forEach((sortable) => sortable.destroy())
    this.sortables = []
  },

  build() {
    this.teardown()

    this.sortables = [
      ...this.buildSlotLists(),
      this.buildRowList(),
      this.buildNewRowZone(),
    ].filter(Boolean)
  },

  /* Chips move within and between rows. */
  buildSlotLists() {
    return Array.from(this.el.querySelectorAll('.var-layout-slots')).map((list) =>
      Sortable.create(list, {
        group: CHIP_GROUP,
        draggable: '.var-chip',
        // No handle and nothing filtered: the whole chip drags, buttons included.
        // A quarter-width chip has too little header to aim at, and the hover
        // actions cover what there is. Sortable only starts a drag once the
        // pointer moves, so the chip's own buttons still take their clicks.
        animation: 150,
        ghostClass: 'is-sorting',
        dragClass: 'is-dragging',
        swapThreshold: 0.6,
        onEnd: () => this.push(),
      })
    )
  },

  /* Whole rows reorder by their gutter handle. */
  buildRowList() {
    const rows = this.el.querySelector('.var-layout-rows-inner')
    if (!rows) return null

    return Sortable.create(rows, {
      group: ROW_GROUP,
      draggable: '.var-layout-row',
      handle: '.var-row-handle',
      animation: 150,
      ghostClass: 'is-sorting',
      onEnd: () => this.push(),
    })
  },

  /* Dropping into the trailing zone starts a fresh row. */
  buildNewRowZone() {
    const zone = this.el.querySelector('[data-var-layout-new-row]')
    if (!zone) return null

    return Sortable.create(zone, {
      group: CHIP_GROUP,
      draggable: '.var-chip',
      animation: 150,
      onAdd: () => this.push(),
    })
  },

  /* The DOM is the description of the drop; the server derives the rest. */
  serialize() {
    const rows = Array.from(this.el.querySelectorAll('.var-layout-row'))
      .map((row) =>
        Array.from(row.querySelectorAll('.var-chip')).map((chip) => chip.dataset.key)
      )
      .filter((row) => row.length)

    const zone = this.el.querySelector('[data-var-layout-new-row]')
    const spilled = zone
      ? Array.from(zone.querySelectorAll('.var-chip')).map((chip) => chip.dataset.key)
      : []

    return spilled.length ? [...rows, spilled] : rows
  },

  push() {
    this.pushEventTo(this.target, 'reposition_vars', {
      rows: this.serialize(),
      surface: this.el.dataset.surface,
    })
  },
})
