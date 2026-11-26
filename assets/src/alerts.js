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

import { openDialog as openNativeDialog, closeDialog, resetDialog, isBackdropClick } from './nativeDialogMotion'

// Fills `el` with a message: text, or `{ html }` for server-escaped markup.
function fill(el, message) {
  if (message && typeof message === 'object') el.innerHTML = message.html || ''
  else el.textContent = message || ''
}

function empty(message) {
  return message && typeof message === 'object' ? !message.html : !message
}

// A radio group under the message (`choice`: `{ name, legend, options }`, or
// a list of them),
// as a delete dialog asks what becomes of what the entry holds. An option
// may carry a `select` (`{ name, label, selected, options }`), enabled while
// its option is checked. All of it is text.
function buildChoice({ name, legend, options }) {
  const $fieldset = document.createElement('fieldset')
  $fieldset.className = 'admin-dialog-choice'

  const $legend = document.createElement('legend')
  $legend.textContent = legend || ''
  $fieldset.appendChild($legend)

  const selects = []
  const groupName = `admin-dialog-choice-${Math.random().toString(36).slice(2)}`

  for (const option of options || []) {
    const id = `${groupName}-${option.value}`
    const $option = document.createElement('div')
    $option.className = 'admin-dialog-option'

    const $radio = document.createElement('input')
    $radio.type = 'radio'
    $radio.name = groupName
    $radio.id = id
    $radio.value = option.value
    $radio.checked = !!option.checked
    $radio.dataset.choiceName = name

    const $label = document.createElement('label')
    $label.htmlFor = id
    $label.textContent = option.label

    $option.append($radio, $label)

    if (option.select) {
      const $select = document.createElement('select')
      $select.className = 'admin-select'
      $select.name = option.select.name
      $select.setAttribute('aria-label', option.select.label || option.label)

      for (const { value, label } of option.select.options || []) {
        const $opt = document.createElement('option')
        $opt.value = value
        $opt.textContent = label
        $opt.selected = value === option.select.selected
        $select.appendChild($opt)
      }

      selects.push({ $radio, $select })
      $option.appendChild($select)
    }

    if (option.hint) {
      const $hint = document.createElement('p')
      $hint.className = 'admin-dialog-hint'
      $hint.textContent = option.hint
      $option.appendChild($hint)
    }

    $fieldset.appendChild($option)
  }

  const sync = () => selects.forEach(({ $radio, $select }) => ($select.disabled = !$radio.checked))
  $fieldset.addEventListener('change', sync)
  sync()

  const values = () => {
    const checked = $fieldset.querySelector('input[type=radio]:checked')
    if (!checked) return {}
    const result = { [name]: checked.value }
    for (const { $radio, $select } of selects) {
      if ($radio === checked) result[$select.name] = $select.value
    }
    return result
  }

  return { $fieldset, values }
}

function openDialog({ title, message, tone, buttons, choice }) {
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

  // One choice, or several (a page's fragments and its translations)
  const choices = [].concat(choice || []).filter(c => c.options && c.options.length).map(buildChoice)
  choices.forEach(({ $fieldset }) => dialog.appendChild($fieldset))
  const built = choices.length ? { values: () => Object.assign({}, ...choices.map(c => c.values())) } : null

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
      // With a choice, confirming answers with its values
      button.addEventListener('click', () => close(value && built ? built.values() : value))
      $actions.appendChild(button)
    }

    // Clicking the backdrop (outside the dialog's box) cancels.
    // No click in the dialog reaches the page: the page's click-away handlers
    // (LiveView's `phx-click-away`, the dropdowns) listen for it bubbling to
    // document and window, and would close the menu the dialog was opened from,
    // taking the focus the dialog hands back with it.
    dialog.addEventListener('click', e => {
      e.stopPropagation()
      if (isBackdropClick(e, dialog)) close()
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
// delete by accident. With a `choice`, the callback is given its values
// (an object) when confirmed, and `false` when not.
function alertConfirm(title, message, callback = () => {}, { confirmText, cancelText, destructive, choice } = {}) {
  const { ok, cancel } = labels()

  openDialog({
    title,
    message,
    choice,
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
