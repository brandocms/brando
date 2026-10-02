// Alerts and confirmations on the native <dialog> element. showModal() puts it
// in the top layer, keeps focus inside it and closes it on Escape.
//
// Button labels come from the server, translated: per call, or the defaults
// the admin layout puts on <body> (data-confirm-ok / data-confirm-cancel).
//
// `title` and `html` are trusted markup: alerts pushed from the server carry
// links (a download, a share URL). Callers with user text escape it first —
// see confirm.js.

function openDialog({ title, html, tone, buttons }) {
  const dialog = document.createElement('dialog')
  dialog.className = `admin-dialog${tone ? ` admin-dialog--${tone}` : ''}`

  const titleId = `admin-dialog-title-${Math.random().toString(36).slice(2)}`
  const heading = title || html
  const body = title ? html : ''

  dialog.setAttribute('aria-labelledby', titleId)
  dialog.innerHTML = `
    <h2 id="${titleId}" class="admin-dialog-title"></h2>
    <div class="admin-dialog-body"></div>
    <div class="admin-dialog-actions"></div>
  `
  dialog.querySelector('.admin-dialog-title').innerHTML = heading || ''
  const $body = dialog.querySelector('.admin-dialog-body')
  if (body) $body.innerHTML = body
  else $body.remove()

  const $actions = dialog.querySelector('.admin-dialog-actions')

  return new Promise(resolve => {
    let result = false

    for (const { label, value, kind, focus } of buttons) {
      const button = document.createElement('button')
      button.type = 'button'
      button.className = `admin-dialog-button${kind ? ` ${kind}` : ''}`
      button.textContent = label
      button.autofocus = !!focus
      button.addEventListener('click', () => {
        result = value
        dialog.close()
      })
      $actions.appendChild(button)
    }

    // Clicking the backdrop (the dialog element itself, outside its box) cancels.
    dialog.addEventListener('click', e => {
      if (e.target === dialog) dialog.close()
    })

    dialog.addEventListener('close', () => {
      dialog.remove()
      resolve(result)
    })

    document.body.appendChild(dialog)
    dialog.showModal()
  })
}

function labels() {
  const defaults = document.body.dataset
  return { ok: defaults.confirmOk || 'OK', cancel: defaults.confirmCancel || 'Cancel' }
}

function alert(tone) {
  return (title, html, callback = () => {}) =>
    openDialog({
      title,
      html,
      tone,
      buttons: [{ label: labels().ok, value: true, kind: 'is-primary', focus: true }]
    }).then(callback)
}

const alertError = alert('error')
const alertWarning = alert('warning')
const alertInfo = alert(null)

// `destructive`: a red confirm button, and focus on Cancel, so Enter doesn't
// delete by accident.
function alertConfirm(title, html, callback = () => {}, { confirmText, cancelText, destructive } = {}) {
  const { ok, cancel } = labels()

  openDialog({
    title,
    html,
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
