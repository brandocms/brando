import { alertConfirm } from '../../alerts'

/**
 * The calendar's days and items (BrandoAdmin.CalendarLive).
 *
 * Keyboard: the days are one tab stop. Arrow keys move between them (up and
 * down by a week in the grid, by a day in the phone's list), Home and End to
 * the week's first and last day, Enter into the day's first item, and Escape
 * from an item back to its day. Each item's link and "Move to…" button are
 * ordinary controls; the button is the keyboard's (and touch's) way to move.
 *
 * Dragging an item that may be moved onto another day asks the LiveView what
 * that would do (`describe_move`), asks the user, and only then moves it
 * (`move`). The time of day stays, so the server works it out; the drop only
 * names the day.
 */
export default () => ({
  mounted() {
    this.onKeydown = e => this.keydown(e)
    this.onDragStart = e => this.dragStart(e)
    this.onDragOver = e => this.dragOver(e)
    this.onDragLeave = e => this.dragLeave(e)
    this.onDrop = e => this.drop(e)
    this.onDragEnd = () => this.dragEnd()
    this.onFocusIn = e => this.focusIn(e)

    this.el.addEventListener('keydown', this.onKeydown)
    this.el.addEventListener('dragstart', this.onDragStart)
    this.el.addEventListener('dragover', this.onDragOver)
    this.el.addEventListener('dragleave', this.onDragLeave)
    this.el.addEventListener('drop', this.onDrop)
    this.el.addEventListener('dragend', this.onDragEnd)
    this.el.addEventListener('focusin', this.onFocusIn)
  },

  destroyed() {
    this.el.removeEventListener('keydown', this.onKeydown)
    this.el.removeEventListener('dragstart', this.onDragStart)
    this.el.removeEventListener('dragover', this.onDragOver)
    this.el.removeEventListener('dragleave', this.onDragLeave)
    this.el.removeEventListener('drop', this.onDrop)
    this.el.removeEventListener('dragend', this.onDragEnd)
    this.el.removeEventListener('focusin', this.onFocusIn)
  },

  // The days shown: on a phone, days with nothing planned are hidden
  days() {
    return [...this.el.querySelectorAll('[data-calendar-day]')].filter(day => day.checkVisibility())
  },

  isList() {
    return getComputedStyle(this.el.querySelector('.calendar-days')).display !== 'grid'
  },

  // One tab stop: the day that has, or last had, the focus. Through sticky JS,
  // so a patch keeps it.
  setTabStop(day) {
    for (const other of this.el.querySelectorAll('[data-calendar-day][tabindex="0"]')) {
      if (other !== day) this.js().setAttribute(other, 'tabindex', '-1')
    }
    this.js().setAttribute(day, 'tabindex', '0')
  },

  focusIn(e) {
    const day = e.target.closest('[data-calendar-day]')
    if (day && e.target === day) this.setTabStop(day)
  },

  keydown(e) {
    const day = e.target.closest('[data-calendar-day]')
    if (!day) return

    if (e.target !== day) {
      if (e.key === 'Escape') {
        e.preventDefault()
        day.focus()
      }
      return
    }

    const days = this.days()
    const index = days.indexOf(day)
    const weekStep = this.isList() ? 1 : 7
    let target = null

    switch (e.key) {
      case 'ArrowLeft':
        target = days[index - 1]
        break
      case 'ArrowRight':
        target = days[index + 1]
        break
      case 'ArrowUp':
        target = days[index - weekStep]
        break
      case 'ArrowDown':
        target = days[index + weekStep]
        break
      case 'Home':
        target = this.isList() ? days[0] : days[index - (index % 7)]
        break
      case 'End':
        target = this.isList() ? days[days.length - 1] : days[Math.min(index - (index % 7) + 6, days.length - 1)]
        break
      case 'Enter': {
        const first = day.querySelector('.calendar-item a') || day.querySelector('.calendar-item button')
        if (first) {
          e.preventDefault()
          first.focus()
        }
        return
      }
      default:
        return
    }

    e.preventDefault()
    if (target) {
      this.setTabStop(target)
      target.focus()
    }
  },

  dragStart(e) {
    const item = e.target.closest?.('[data-calendar-item][draggable="true"]')
    if (!item) return

    this.dragging = {
      item: item.dataset.calendarItem,
      from: item.closest('[data-calendar-day]').dataset.calendarDay
    }
    e.dataTransfer.effectAllowed = 'move'
    e.dataTransfer.setData('text/plain', this.dragging.item)
    item.classList.add('is-dragging')
  },

  dragOver(e) {
    if (!this.dragging) return
    const day = e.target.closest('[data-calendar-day]')
    if (!day) return

    e.preventDefault()
    e.dataTransfer.dropEffect = 'move'
    this.markTarget(day.dataset.calendarDay === this.dragging.from ? null : day)
  },

  dragLeave(e) {
    if (!this.dragging) return
    const day = e.target.closest('[data-calendar-day]')
    if (day && !day.contains(e.relatedTarget)) day.classList.remove('is-drop-target')
  },

  markTarget(day) {
    for (const other of this.el.querySelectorAll('.is-drop-target')) {
      if (other !== day) other.classList.remove('is-drop-target')
    }
    day?.classList.add('is-drop-target')
  },

  drop(e) {
    const dragging = this.dragging
    const day = e.target.closest('[data-calendar-day]')
    if (!dragging || !day) return

    e.preventDefault()
    this.dragEnd()

    const date = day.dataset.calendarDay
    if (date === dragging.from) return

    this.pushEvent('describe_move', { item: dragging.item, date }, reply => {
      if (!reply || reply.error) return

      alertConfirm(
        reply.title,
        reply.message,
        confirmed => {
          if (confirmed) this.pushEvent('move', { item: dragging.item, date })
        },
        { confirmText: reply.confirm }
      )
    })
  },

  dragEnd() {
    this.dragging = null
    this.markTarget(null)
    for (const item of this.el.querySelectorAll('.is-dragging')) item.classList.remove('is-dragging')
  }
})
