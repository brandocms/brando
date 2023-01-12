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

function alertConfirm(title, html, callback) {
  if (!callback) {
    callback = () => {}
  }

  Swal.fire({
    title,
    html,
    icon: 'question',
    showCancelButton: true,
    cancelButtonText: 'Cancel/Avbryt',
    confirmButtonText: 'OK'
  }).then(result => {
    if (result.isConfirmed) {
      callback(true)
    } else {
      callback(false)
    }
  })
}

export { alertError, alertInfo, alertSuccess, alertWarning, alertConfirm, alertPrompt }
