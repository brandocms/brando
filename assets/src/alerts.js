// Alerts and confirmations on the native <dialog> element. showModal() puts it
// in the top layer, keeps focus inside it and closes it on Escape.
//
// Button labels come from the server, translated: per call, or the defaults
// the admin layout puts on <body> (data-confirm-ok / data-confirm-cancel).
//
// `title` and `message` are text. A message that needs markup (a download
// link, a list of fields) is passed as `{ html }`, and only with markup the
// server built and escaped: alerts carry names, filenames and titles other
// admins control.

import { openDialog as openNativeDialog, closeDialog, resetDialog } from './nativeDialogMotion'

// Fills `el` with a message: text, or `{ html }` for server-escaped markup.
function fill(el, message) {
  if (message && typeof message === 'object') el.innerHTML = message.html || ''
  else el.textContent = message || ''
}

function empty(message) {
  return message && typeof message === 'object' ? !message.html : !message
}

function openDialog({ title, message, tone, buttons }) {
  const dialog = document.createElement('dialog')
  dialog.className = `admin-dialog${tone ? ` admin-dialog--${tone}` : ''}`

  const titleId = `admin-dialog-title-${Math.random().toString(36).slice(2)}`
  // Without a title the message is the heading.
  const heading = title || message
  const body = title ? message : ''

  dialog.setAttribute('aria-labelledby', titleId)

  const $title = document.createElement('h2')
  $title.id = titleId
  $title.className = 'admin-dialog-title'
  fill($title, heading)
  dialog.appendChild($title)

  if (!empty(body)) {
    const $body = document.createElement('div')
    $body.className = 'admin-dialog-body'
    fill($body, body)
    dialog.appendChild($body)
  }

  const $actions = document.createElement('div')
  $actions.className = 'admin-dialog-actions'
  dialog.appendChild($actions)

  return new Promise(resolve => {
    let result = false
    const motion = { dialog }
    const close = (value = false) => {
      // Keep the first decision while fading out, even if Escape or another
      // button is pressed before the dialog has left the top layer.
      if (motion.closing) return
      result = value
      closeDialog(motion)
    }

    for (const { label, value, kind, focus } of buttons) {
      const button = document.createElement('button')
      button.type = 'button'
      button.className = `admin-dialog-button${kind ? ` ${kind}` : ''}`
      button.textContent = label
      button.autofocus = !!focus
      button.addEventListener('click', () => close(value))
      $actions.appendChild(button)
    }

    // Clicking the backdrop (the dialog element itself, outside its box) cancels.
    dialog.addEventListener('click', e => {
      if (e.target === dialog) close()
    })

    dialog.addEventListener('cancel', e => {
      e.preventDefault()
      close()
    })

    dialog.addEventListener('close', () => {
      resetDialog(motion)
      dialog.remove()
      resolve(result)
    })

    document.body.appendChild(dialog)
    openNativeDialog(motion)
  })
}

function labels() {
  const defaults = document.body.dataset
  return { ok: defaults.confirmOk || 'OK', cancel: defaults.confirmCancel || 'Cancel' }
}

function alert(tone) {
  return (title, message, callback = () => {}) =>
    openDialog({
      title,
      message,
      tone,
      buttons: [{ label: labels().ok, value: true, kind: 'is-primary', focus: true }]
    }).then(callback)
}

const alertError = alert('error')
const alertWarning = alert('warning')
const alertInfo = alert(null)

// `destructive`: a red confirm button, and focus on Cancel, so Enter doesn't
// delete by accident.
function alertConfirm(title, message, callback = () => {}, { confirmText, cancelText, destructive } = {}) {
  const { ok, cancel } = labels()

  openDialog({
    title,
    message,
    tone: destructive ? 'destructive' : null,
    buttons: [
      { label: cancelText || cancel, value: false, focus: !!destructive },
      {
        label: confirmText || ok,
        value: true,
        kind: destructive ? 'is-danger' : 'is-primary',
        focus: !destructive
      }
    ]
  }).then(confirmed => callback(confirmed))
}

export { alertError, alertInfo, alertWarning, alertConfirm }
