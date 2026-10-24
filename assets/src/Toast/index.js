import { animate, set } from '../motion'

// One stack of toasts in the bottom right corner, for two kinds of message:
//
// - notifications answer something the user did (`notification/2`): success
//   and info fade after a while, errors stay until closed;
// - mutations tell them what someone else just changed (`mutation/2`): quiet,
//   with the editor's initials, gone after a few seconds;
// - background work they started (`work/1`, BrandoAdmin.Work): one toast per
//   work, updated in place, with a spinner, or a bar when it knows how far it
//   has come, until it turns into its result. A page that shows the work
//   itself (an element with its `data-work-id`) gets no toast for it.
//
// Messages are set as text, never HTML: mutations carry entry titles.

const TIMEOUTS = { success: 5000, info: 5000, mutation: 4000 }
const MAX_VISIBLE = 5

export default class Toast {
  constructor(app) {
    this.app = app
    this.popupTimer = null
    this.popup = null
    // Work id → { entry, toast, dismissed }
    this.workState = new Map()

    this.stack = document.createElement('div')
    this.stack.className = 'toast-stack'
    // Polite: new toasts are read out without interrupting the user.
    this.stack.setAttribute('role', 'status')
    this.stack.setAttribute('aria-live', 'polite')
    document.body.appendChild(this.stack)
  }

  notification(level, message) {
    if (!['success', 'error', 'info'].includes(level)) return
    this.add({ kind: level, text: message })
  }

  mutation(_level, payload) {
    const { user, action, identifier } = payload
    const name = (user && user.name) || 'System'

    this.add({
      kind: 'mutation',
      initials: initials(name),
      build: $text => {
        const who = document.createElement('strong')
        who.textContent = name
        const what = document.createElement('span')
        what.className = 'toast-mono'
        what.textContent = `${identifier.type} #${identifier.entry_id}`
        $text.append(who, ` ${action} `, what, ` “${identifier.title}”`)
      }
    })
  }

  // The socket dropped: say so until it is back, then confirm it briefly.
  connection(connected, message) {
    this.remove(this.connectionToast)
    this.connectionToast = this.add({ kind: connected ? 'success' : 'error', text: message })
  }

  // A report of background work: shows, updates or ends its toast. A work
  // keeps its toast while its result shows, so the same key running again
  // turns that toast back into progress rather than adding a second.
  work(entry) {
    const state = this.workState.get(entry.id) || {}
    if (entry.status === 'running' && state.entry && state.entry.status !== 'running') {
      state.dismissed = false
    }
    state.entry = entry
    this.workState.set(entry.id, state)
    this.renderWork(entry.id)
  }

  // The work running when the user channel (re)joins. Work that ended while
  // the socket was down leaves quietly: its result was missed.
  syncWork(entries) {
    const running = new Set(entries.map(entry => entry.id))
    for (const [id, state] of this.workState) {
      if (state.entry.status === 'running' && !running.has(id)) this.forgetWork(id)
    }
    entries.forEach(entry => this.work(entry))
  }

  // After navigating, or when the page shows or drops a work's status
  // (the WorkStatus hook): a page that shows a work inline takes over from
  // its toast, and leaving it brings the toast back.
  refreshWork() {
    for (const id of [...this.workState.keys()]) this.renderWork(id)
  }

  forgetWork(id) {
    const state = this.workState.get(id)
    if (state) this.remove(state.toast)
    this.workState.delete(id)
  }

  renderWork(id) {
    const state = this.workState.get(id)
    if (!state) return
    const { entry } = state
    const running = entry.status === 'running'
    // The toast carries the id too
    const inline =
      entry.toast !== 'always' &&
      document.querySelector(`[data-work-id="${CSS.escape(id)}"]:not(.toast)`)

    if (inline || (running && state.dismissed)) {
      if (running) {
        this.remove(state.toast)
        state.toast = null
      } else {
        this.forgetWork(id)
      }
      return
    }

    let toast = state.toast
    if (!toast || !toast.isConnected || toast.classList.contains('leaving')) {
      toast = this.add({
        kind: 'work',
        build: () => {},
        onClose: () => {
          state.dismissed = true
        }
      })
      toast.dataset.workId = id
      toast.onRemoved = () => {
        if (state.toast !== toast) return
        // A result's toast that goes takes its work along; a running one
        // pushed out by newer toasts stays out until it ends
        if (state.entry.status !== 'running') this.workState.delete(id)
        else if (toast.evicted) state.dismissed = true
      }
      state.toast = toast
    } else if (running && !toast.classList.contains('toast--work')) {
      toast.classList.remove('toast--success', 'toast--error')
      toast.classList.add('toast--work')
      toast.querySelector('.toast-dot')?.classList.replace('toast-dot', 'toast-spinner')
      this.expire(toast, null)
    }

    fillWork(toast, entry)

    // Only as it ends: a refresh must not set the fade going again
    if (!running && toast.classList.contains('toast--work')) {
      const kind = entry.status === 'finished' ? 'success' : 'error'
      toast.classList.replace('toast--work', `toast--${kind}`)
      toast.querySelector('.toast-spinner')?.classList.replace('toast-spinner', 'toast-dot')
      this.expire(toast, TIMEOUTS[kind])
    }
  }

  add({ kind, text, initials, build, onClose }) {
    const toast = document.createElement('div')
    toast.className = `toast toast--${kind}`

    const marker = document.createElement('span')
    if (initials) {
      marker.className = 'toast-initials'
      marker.textContent = initials
    } else if (kind === 'work') {
      marker.className = 'toast-spinner'
    } else {
      marker.className = 'toast-dot'
    }

    const $text = document.createElement('div')
    $text.className = 'toast-text'
    if (build) build($text)
    else $text.textContent = text

    toast.append(marker, $text)

    if (kind !== 'mutation') {
      const close = document.createElement('button')
      close.type = 'button'
      close.className = 'toast-close'
      close.setAttribute('aria-label', document.body.dataset.toastClose || 'Close')
      close.textContent = '×'
      close.addEventListener('click', () => {
        if (onClose) onClose()
        this.remove(toast)
      })
      toast.append(close)
    }

    this.stack.append(toast)
    animate(toast, { opacity: [0, 1], y: [8, 0] }, { duration: 0.18 })

    this.expire(toast, TIMEOUTS[kind])

    const toasts = this.stack.querySelectorAll('.toast:not(.leaving)')
    if (toasts.length > MAX_VISIBLE) {
      toasts[0].evicted = true
      this.remove(toasts[0])
    }

    return toast
  }

  // Fades the toast after `timeout` ms; none keeps it until closed (and
  // stops a fade already set).
  expire(toast, timeout) {
    clearTimeout(toast.expiryTimer)
    toast.expires = Boolean(timeout)
    if (!timeout) return
    toast.expiryTimer = setTimeout(() => this.remove(toast), timeout)

    if (toast.holdsOnHover) return
    toast.holdsOnHover = true
    // Hovering holds a toast so it can be read.
    toast.addEventListener('mouseenter', () => clearTimeout(toast.expiryTimer))
    toast.addEventListener('mouseleave', () => {
      clearTimeout(toast.expiryTimer)
      if (toast.expires) toast.expiryTimer = setTimeout(() => this.remove(toast), 1500)
    })
  }

  remove(toast) {
    if (!toast || !toast.isConnected || toast.classList.contains('leaving')) return
    toast.classList.add('leaving')
    clearTimeout(toast.expiryTimer)
    if (toast.onRemoved) toast.onRemoved()
    animate(toast, { opacity: 0 }, { duration: 0.2 }).finished.then(() => toast.remove())
  }

  progressPopup(message) {
    // kill the close timer (if it exists)
    this.popupTimer && clearTimeout(this.popupTimer)

    this.popupTimer = setTimeout(() => {
      this.closePopup()
    }, 800)
    this.updatePopup(message)
  }

  updatePopup(message) {
    if (!this.popup) {
      this.msgNo = 1
      this.popup = document.createElement('div')
      this.popup.className = 'progress-popup'
      this.popup.innerHTML = `<div class="message">[${this.msgNo}] &rarr; ${message}</div>`
      set(this.popup, { opacity: 0 })
      document.body.appendChild(this.popup)
      this.popup.setAttribute('popover', '')
      if (typeof this.popup.showPopover === 'function') {
        this.popup.showPopover()
      }
      animate(this.popup, { opacity: 1 }, { duration: 0.15 })
    } else {
      this.msgNo++
      this.popup.querySelector('.message').innerHTML =
        `[${this.msgNo}] &rarr; ${message}`
      // A message during the fade-out brings the popup back. Starting a new
      // opacity animation stops the fade, and a stopped fade never finishes,
      // so the popup is not removed under the new message.
      animate(this.popup, { opacity: 1 }, { duration: 0.15 })
    }
  }

  closePopup() {
    const popup = this.popup
    if (popup) {
      animate(popup, { opacity: 0 }, { duration: 0.5 }).finished.then(() => {
        popup.remove()
        this.popup = null
      })
    }
  }
}

// The work's message, and its bar and count while it runs. Text only.
function fillWork(toast, entry) {
  const $text = toast.querySelector('.toast-text')
  const running = entry.status === 'running'
  const words = document.body.dataset
  const fallback = entry.timed_out
    ? words.workTimedOut
    : entry.status === 'finished'
      ? words.workDone
      : entry.status === 'failed'
        ? words.workFailed
        : ''

  const message = document.createElement('span')
  message.textContent = entry.message || fallback || ''
  $text.replaceChildren(message)

  if (running && entry.total) {
    const count = document.createElement('span')
    count.className = 'toast-mono toast-count'
    count.textContent = `${entry.done} / ${entry.total}`
    $text.append(count)
  }

  if (running && entry.percent != null) {
    const bar = document.createElement('span')
    bar.className = 'toast-progress'
    bar.setAttribute('role', 'progressbar')
    bar.setAttribute('aria-valuemin', '0')
    bar.setAttribute('aria-valuemax', '100')
    bar.setAttribute('aria-valuenow', String(entry.percent))
    const fill = document.createElement('span')
    fill.style.width = `${entry.percent}%`
    bar.append(fill)
    $text.append(bar)
  }
}

function initials(name) {
  return name
    .split(/\s+/)
    .filter(Boolean)
    .slice(0, 2)
    .map(part => part[0].toUpperCase())
    .join('')
}
