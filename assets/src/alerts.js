import Swal from 'sweetalert2/src/sweetalert2.js'

function alertError(title, html, callback) {
  if (!callback) {
    callback = () => {}
  }

  Swal.fire({
    title,
    html,
    icon: 'error',
    confirmButtonText: 'OK'
  })
}

function alertInfo(title, html, callback) {
  if (!callback) {
    callback = () => {}
  }

  Swal.fire({
    title,
    html,
    icon: 'info',
    confirmButtonText: 'OK'
  })
}

function alertSuccess(title, html, callback) {
  if (!callback) {
    callback = () => {}
  }

  Swal.fire({
    title,
    html,
    icon: 'success',
    confirmButtonText: 'OK'
  })
}

function alertWarning(title, html, callback) {
  if (!callback) {
    callback = () => {}
  }

  Swal.fire({
    title,
    html,
    icon: 'warning',
    confirmButtonText: 'OK'
  })
}

async function alertPrompt(html, value, callback) {
  if (!callback) {
    callback = () => {}
  }

  const { value: data } = await Swal.fire({
    input: 'text',
    inputLabel: '',
    inputValue: value,
    html,
    confirmButtonText: 'OK'
  })
  callback({ data })
}

// Button labels come from the server, translated: per call, or the defaults
// the admin layout puts on <body> (data-confirm-ok / data-confirm-cancel).
// `destructive`: a red confirm button, and focus on Cancel, so Enter doesn't
// delete by accident.
function alertConfirm(title, html, callback, { confirmText, cancelText, destructive } = {}) {
  if (!callback) {
    callback = () => {}
  }

  const defaults = document.body.dataset

  Swal.fire({
    title,
    html,
    icon: destructive ? 'warning' : 'question',
    showCancelButton: true,
    focusCancel: !!destructive,
    customClass: destructive ? { confirmButton: 'swal2-destructive' } : {},
    cancelButtonText: cancelText || defaults.confirmCancel || 'Cancel',
    confirmButtonText: confirmText || defaults.confirmOk || 'OK'
  }).then(result => {
    if (result.isConfirmed) {
      callback(true)
    } else {
      callback(false)
    }
  })
}

export { alertError, alertInfo, alertSuccess, alertWarning, alertConfirm, alertPrompt }
