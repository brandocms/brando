import { motionDuration, prefersReducedMotion } from './motion'

// Native alerts, Search and the shortcut sheet share dialog/backdrop motion.
// Keep the top layer until the exit ends; reopening reverses the CSS fade.
// LiveView-owned dialogs need sticky attributes; alerts own their DOM outright.
const attributes = {
  setAttribute: (el, name, value) => el.setAttribute(name, value),
  removeAttribute: (el, name) => el.removeAttribute(name)
}
const commands = hook => hook.js?.() || attributes

export function openDialog(hook) {
  clearTimeout(hook.closeTimer)
  hook.closing = false
  if (!hook.dialog.open) hook.dialog.showModal()
  commands(hook).setAttribute(hook.dialog, 'data-dialog-open', 'true')
}

export function closeDialog(hook) {
  if (!hook.dialog.open || hook.closing) return
  hook.closing = true
  commands(hook).removeAttribute(hook.dialog, 'data-dialog-open')
  const duration = prefersReducedMotion() ? 0 : motionDuration(hook.dialog, '--motion-leave')
  if (duration <= 1) hook.dialog.close()
  else hook.closeTimer = setTimeout(() => hook.dialog.close(), duration)
}

// `dialog.close()` queues its `close` event. Without motion a dialog can be
// opened again before that event arrives; its close is over by then, and
// handling it would reset the reopened dialog.
export function onDialogClose(hook, callback) {
  hook.dialog.addEventListener('close', () => {
    if (!hook.dialog.open) callback()
  })
}

export function resetDialog(hook) {
  clearTimeout(hook.closeTimer)
  hook.closing = false
  commands(hook).removeAttribute(hook.dialog, 'data-dialog-open')
}
