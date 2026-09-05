// Recovery storage is server-owned. The browser sends the currently visible raw
// values so a debounce or failed cast cannot make an acknowledged copy incomplete.
export default function draftRecovery(hook) {
  let generation = 0
  let pending = false
  let inFlight = false
  let trailing
  let flightTimer
  const enabled = () => hook.el.dataset.draftEnabled === 'true'
  const ours = ({ id }) => id === hook.el.dataset.draftFormId
  const encode = form => {
    const params = new URLSearchParams()
    for (const [key, value] of new FormData(form)) {
      if (!(value instanceof File) && !/password/i.test(key)) params.append(key, value)
    }
    return params.toString()
  }
  const capture = () => {
    if (!enabled() || inFlight || !hook.liveSocket.isConnected()) return
    const form = hook.el.querySelector('form.main-form')
    if (!form) return
    const blocks = {}
    hook.el.querySelectorAll('form[phx-change="validate_block"]').forEach(block => {
      const uid = block.id.replace(/^(entry_block_form|child_block_form)-/, '')
      blocks[uid] = encode(block)
    })
    inFlight = true
    flightTimer = setTimeout(() => { inFlight = false }, 11000)
    hook.pushEventTo(hook.el, 'draft_capture', { main: encode(form), blocks, generation })
  }
  const dirty = () => {
    generation += 1
    pending = true
    clearTimeout(trailing)
    trailing = setTimeout(capture, 2000)
  }
  const onInput = event => {
    if (event.target.closest('form.main-form, form[phx-change="validate_block"]')) dirty()
  }
  const beforeUnload = event => {
    if (pending) { event.preventDefault(); event.returnValue = '' }
  }
  const beforeNavigate = event => {
    if (!pending || event.defaultPrevented || event.button !== 0 || event.metaKey || event.ctrlKey || event.shiftKey || event.altKey) return
    const link = event.target.closest('a[data-phx-link]')
    if (!link || link.hasAttribute('download') || link.target === '_blank') return
    if (new URL(link.href).pathname === window.location.pathname) return
    if (!window.confirm(hook.el.dataset.draftLeaveMessage)) {
      event.preventDefault()
      event.stopImmediatePropagation()
    }
  }
  hook.el.addEventListener('input', onInput, true)
  hook.el.addEventListener('change', onInput, true)
  window.addEventListener('beforeunload', beforeUnload)
  window.addEventListener('click', beforeNavigate, true)
  const interval = setInterval(capture, 15000)
  hook.handleEvent('b:draft-dirty', event => { if (ours(event)) dirty() })
  hook.handleEvent('b:draft-saved', event => {
    if (!ours(event)) return
    clearTimeout(flightTimer)
    inFlight = false
    if (event.generation === generation) pending = false
    else trailing = setTimeout(capture, 2000)
  })
  hook.handleEvent('b:draft-reset', event => {
    if (!ours(event)) return
    if (event.clean) pending = false
    inFlight = false
    clearTimeout(trailing)
    clearTimeout(flightTimer)
  })
  return {
    disconnected() { hook.js().addClass(hook.el, 'draft-offline'); inFlight = false },
    reconnected() { hook.js().removeClass(hook.el, 'draft-offline'); capture() },
    destroy() {
      clearTimeout(trailing); clearTimeout(flightTimer); clearInterval(interval)
      hook.el.removeEventListener('input', onInput, true)
      hook.el.removeEventListener('change', onInput, true)
      window.removeEventListener('beforeunload', beforeUnload)
      window.removeEventListener('click', beforeNavigate, true)
    },
  }
}
