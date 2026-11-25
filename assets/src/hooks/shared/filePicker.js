// A hook can open the chooser again after cancellation or disappear while
// the dialog is open. Drop the callback (which may name a replacement row)
// as soon as the dialog closes or the hook goes away.
export default function filePicker() {
  const input = document.createElement('input')
  input.type = 'file'
  input.hidden = true

  function close() {
    input.onchange = null
    input.oncancel = null
    input.value = ''
    input.remove()
  }

  return {
    open(parent, accept, multiple, onPick) {
      input.accept = accept.join(',')
      input.multiple = multiple
      input.oncancel = close
      input.onchange = () => {
        const files = Array.from(input.files || [])
        close()
        if (files.length) onPick(files)
      }
      parent.appendChild(input)
      input.click()
    },
    close,
  }
}
