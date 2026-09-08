// Recovery storage is server-owned. The browser sends the currently visible raw
// values so a debounce or failed cast cannot make an acknowledged copy incomplete.
export default function draftRecovery(hook) {
  let generation = 0
  let pending = false
  let inFlight = null
  let saveGeneration = null
  let dirtySince = null
  let lastChanged = 0
  let captureTimer
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
    clearTimeout(captureTimer)
    if (!pending || !enabled() || inFlight || !hook.liveSocket.isConnected()) return
    const form = hook.el.querySelector('form.main-form')
    if (!form) return
    const blocks = {}
    hook.el.querySelectorAll('form[phx-change="validate_block"]').forEach(block => {
      const uid = block.id.replace(/^(entry_block_form|child_block_form)-/, '')
      blocks[uid] = encode(block)
    })
    dirtySince = null
    inFlight = { requestId: crypto.randomUUID(), generation }
    // The server abandons incomplete captures after ten seconds. Retry only
    // unacknowledged work; a timeout must not leave it stranded until another edit.
    flightTimer = setTimeout(() => { inFlight = null; capture() }, 11000)
    hook.pushEventTo(hook.el, 'draft_capture', {
      main: encode(form), blocks, generation, request_id: inFlight.requestId,
    })
  }
  const schedule = () => {
    clearTimeout(captureTimer)
    if (!pending || inFlight || !hook.liveSocket.isConnected()) return
    const deadline = Math.min(lastChanged + 3000, dirtySince + 15000)
    captureTimer = setTimeout(capture, Math.max(0, deadline - Date.now()))
  }
  const dirty = () => {
    if (!enabled()) return
    generation += 1
    pending = true
    lastChanged = Date.now()
    dirtySince ??= lastChanged
    schedule()
  }
  const onInput = event => {
    if (event.target.closest('form.main-form, form[phx-change="validate_block"]')) dirty()
  }
  const onSubmit = event => {
    if (event.target.matches('form.main-form')) saveGeneration = generation
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
  const copyContent = async event => {
    const button = event.target.closest('[data-draft-copy]')
    if (!button || !hook.el.contains(button)) return
    const source = document.getElementById(button.dataset.draftCopy)
    if (!source || !hook.el.contains(source)) return

    try {
      await navigator.clipboard.writeText(source.tagName === 'PRE' ? source.textContent : source.innerText)
      if (button.isConnected) hook.js().setAttribute(button, 'data-copy-state', 'copied')
    } catch {
      // Clipboard permission can be unavailable; leave the content selected.
      const range = document.createRange()
      range.selectNodeContents(source)
      const selection = window.getSelection()
      selection.removeAllRanges()
      selection.addRange(range)
      if (button.isConnected) hook.js().setAttribute(button, 'data-copy-state', 'failed')
    }
  }
  hook.el.addEventListener('input', onInput, true)
  hook.el.addEventListener('change', onInput, true)
  hook.el.addEventListener('submit', onSubmit, true)
  hook.el.addEventListener('click', copyContent)
  window.addEventListener('beforeunload', beforeUnload)
  window.addEventListener('click', beforeNavigate, true)
  hook.handleEvent('b:draft-dirty', event => { if (ours(event)) dirty() })
  hook.handleEvent('b:draft-saved', event => {
    if (!ours(event) || !inFlight || event.request_id !== inFlight.requestId) return
    pending = inFlight.generation !== generation
    clearTimeout(flightTimer)
    inFlight = null
    if (!pending) dirtySince = null
    schedule()
  })
  hook.handleEvent('b:draft-reset', event => {
    if (!ours(event)) return
    // A server save can finish before newer browser input has been validated.
    // Never acknowledge input typed after the submit that this reset belongs to.
    if (!event.clean) pending = true
    if (event.clean && (saveGeneration === null || saveGeneration === generation)) pending = false
    saveGeneration = null
    inFlight = null
    dirtySince = pending ? Date.now() : null
    lastChanged = Date.now()
    clearTimeout(flightTimer)
    schedule()
  })
  return {
    disconnected() {
      hook.js().addClass(hook.el, 'draft-offline')
      inFlight = null
      clearTimeout(captureTimer)
      clearTimeout(flightTimer)
    },
    reconnected() { hook.js().removeClass(hook.el, 'draft-offline'); capture() },
    destroy() {
      clearTimeout(captureTimer); clearTimeout(flightTimer)
      hook.el.removeEventListener('input', onInput, true)
      hook.el.removeEventListener('change', onInput, true)
      hook.el.removeEventListener('submit', onSubmit, true)
      hook.el.removeEventListener('click', copyContent)
      window.removeEventListener('beforeunload', beforeUnload)
      window.removeEventListener('click', beforeNavigate, true)
    },
  }
}
