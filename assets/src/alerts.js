import Swal from 'sweetalert2/dist/sweetalert2.js'

function alertError(title, text, callback) {
  if (!callback) {
    callback = () => {}
  }

  Swal.fire({
    title,
    text,
    icon: 'error',
    confirmButtonText: 'OK'
  })
}

function alertInfo(title, text, callback) {
  if (!callback) {
    callback = () => {}
  }

  Swal.fire({
    title,
    text,
    icon: 'info',
    confirmButtonText: 'OK'
  })
}

function alertSuccess(title, text, callback) {
  if (!callback) {
    callback = () => {}
  }

  Swal.fire({
    title,
    text,
    icon: 'success',
    confirmButtonText: 'OK'
  })
}

function alertWarning(title, text, callback) {
  if (!callback) {
    callback = () => {}
  }

  Swal.fire({
    title,
    text,
    icon: 'warning',
    confirmButtonText: 'OK'
  })
}

async function alertPrompt(text, value, callback) {
  if (!callback) {
    callback = () => {}
  }

  const { value: data } = await Swal.fire({
    input: 'text',
    inputLabel: '',
    inputValue: value,
    text: text,
    confirmButtonText: 'OK'
  })
  callback({ data })
}

function alertConfirm(title, text, callback) {
  if (!callback) {
    callback = () => {}
  }

  Swal.fire({
    title,
    text,
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
