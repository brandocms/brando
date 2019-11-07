import vex from 'vex-js'
import vexDialog from 'vex-dialog'

vex.registerPlugin(vexDialog)
vex.defaultOptions.className = 'vex-theme-kurtz'

function alertError (title, text, callback) {
  if (!callback) {
    callback = () => {}
  }
  vex.dialog.open({
    unsafeMessage: `
      <div class="text-center text-danger text-lg">
        <i class="fa fa-exclamation-circle fa-5x"></i>
      </div>
      <div class="text-center text-lg mt-3 mb-3 dialog-title">
        <strong>${title}</strong>
      </div>
      <div class="text-center">
        ${text}
      </div>
    `,
    buttons: [vex.dialog.buttons.YES],
    callback
  })
}

function alertInfo (title, text, callback) {
  if (!callback) {
    callback = () => {}
  }
  vex.dialog.open({
    unsafeMessage: `
      <div class="text-center text-info text-lg">
        <i class="fa fa-info-circle fa-5x"></i>
      </div>
      <div class="text-center text-lg mt-3 mb-3 dialog-title">
        <strong>${title}</strong>
      </div>
      <div class="text-center">
        ${text}
      </div>
    `,
    buttons: [vex.dialog.buttons.YES],
    callback
  })
}

function alertSuccess (title, text, callback) {
  if (!callback) {
    callback = () => {}
  }
  vex.dialog.open({
    unsafeMessage: `
      <div class="text-center text-success text-lg">
        <i class="fa fa-check-circle fa-5x"></i>
      </div>
      <div class="text-center text-lg mt-3 mb-3 dialog-title">
        <strong>${title}</strong>
      </div>
      <div class="text-center">
        ${text}
      </div>
    `,
    buttons: [vex.dialog.buttons.YES],
    callback
  })
}

function alertWarning (title, text, callback) {
  if (!callback) {
    callback = () => {}
  }
  vex.dialog.open({
    unsafeMessage: `
      <div class="text-center text-warning text-lg">
        <i class="fa fa-exclamation-triangle fa-5x"></i>
      </div>
      <div class="text-center text-lg mt-3 mb-3 dialog-title">
        <strong>${title}</strong>
      </div>
      <div class="text-center">
        ${text}
      </div>
    `,
    buttons: [vex.dialog.buttons.YES],
    callback
  })
}

function alertPrompt (text, callback) {
  if (!callback) {
    callback = () => {}
  }
  vex.dialog.open({
    unsafeMessage: `
      <div class="text-center text-danger text-lg">
        <i class="fa fa-exclamation-circle fa-5x"></i>
      </div>
      <div class="text-center mt-3 mb-3">
        ${text}
      </div>
    `,
    input: '<input name="data" type="text" required />',
    showCloseButton: true,
    buttons: [vex.dialog.buttons.YES],
    callback
  })
}

function alertConfirm (title, text, callback) {
  if (!callback) {
    callback = () => {}
  }
  vex.dialog.open({
    unsafeMessage: `
      <div class="text-center text-warning text-lg">
        <i class="fa fa-exclamation-triangle fa-5x"></i>
      </div>
      <div class="text-center text-lg mt-3 mb-3 dialog-title">
        <strong>${title}</strong>
      </div>
      <div class="text-center">
        ${text}
      </div>
    `,
    buttons: [vex.dialog.buttons.YES, { ...vex.dialog.buttons.NO, text: 'Avbryt' }],
    callback
  })
}

export {
  alertError,
  alertInfo,
  alertSuccess,
  alertWarning,
  alertConfirm,
  alertPrompt
}
