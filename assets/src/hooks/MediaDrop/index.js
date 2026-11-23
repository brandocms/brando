import { partition } from '../shared/mediaBatch'

/**
 * MediaDrop — images and videos dropped on a multi block whose module has a
 * `media_drop`, each made into a new child block of that module.
 *
 * The hook sits on the block's drop zone and listens on the whole block
 * (`.block`): a file dropped anywhere on it counts, except on a field that
 * takes files itself (a child's media ref stops the drag there, and a field
 * that handles a drop prevents its default). A child dragged between rows
 * is no file drag and passes through.
 *
 * Per drop:
 *
 *   1. sort out the files the ref's upload would refuse
 *      (`shared/mediaBatch`, by extension as the upload manager checks)
 *      and report them (`media_drop_rejected`)
 *   2. ask the block for one child per remaining file, in the order dropped
 *      (`media_drop`); the reply names each child's ref field and the token
 *      its upload reports back with
 *   3. hand each file to that field's UploadTrigger (`brando:upload-files`),
 *      so it uploads exactly as a file dropped on the field does
 *   4. that upload, not the field, tells the block field when it has
 *      settled (`shared/mediaDropHandover`, `brando:handed-upload-settled`),
 *      which takes it from there (`BlockField` hook, `media_drop_settled`),
 *      wherever the child has moved since. A field not on the page says so
 *      the same way, bubbling from here.
 *
 * While a file is dragged over the block, the block carries
 * `data-media-drop="dragging"`, which styles the zone.
 *
 * Expected markup:
 *
 *   <button phx-hook="Brando.MediaDrop" data-kinds='{"image": {"extensions": [...], "mimetypes": [...], "limit": 4000000}}'>
 */
export default (app) => ({
  mounted() {
    this.block = this.el.closest('.block')

    this.onDragOver = (event) => {
      if (!this.takes(event)) return
      event.preventDefault()
      event.stopPropagation()
      this.setDragging()
    }

    this.onDragLeave = (event) => {
      if (event.relatedTarget && this.block.contains(event.relatedTarget)) return
      this.clearDragging()
    }

    this.onDrop = (event) => {
      if (!this.takes(event)) return
      event.preventDefault()
      event.stopPropagation()
      this.clearDragging()
      this.intake(Array.from(event.dataTransfer.files))
    }

    this.block.addEventListener('dragenter', this.onDragOver)
    this.block.addEventListener('dragover', this.onDragOver)
    this.block.addEventListener('dragleave', this.onDragLeave)
    this.block.addEventListener('drop', this.onDrop)
    this.el.addEventListener('click', () => this.openPicker())
  },

  destroyed() {
    clearTimeout(this.dragTimer)
    this.block.removeEventListener('dragenter', this.onDragOver)
    this.block.removeEventListener('dragover', this.onDragOver)
    this.block.removeEventListener('dragleave', this.onDragLeave)
    this.block.removeEventListener('drop', this.onDrop)
  },

  takes(event) {
    return !event.defaultPrevented && Array.from(event.dataTransfer?.types || []).includes('Files')
  },

  // A field inside the block that takes the file stops the drag before it
  // gets here, so no dragover tells the block the pointer left for it: the
  // state lapses unless another dragover renews it.
  setDragging() {
    this.block.dataset.mediaDrop = 'dragging'
    clearTimeout(this.dragTimer)
    this.dragTimer = setTimeout(() => this.clearDragging(), 200)
  },

  clearDragging() {
    clearTimeout(this.dragTimer)
    delete this.block.dataset.mediaDrop
  },

  kinds() {
    try {
      return JSON.parse(this.el.dataset.kinds || '{}')
    } catch (_) {
      return {}
    }
  },

  openPicker() {
    const kinds = this.kinds()
    const accept = Object.values(kinds).flatMap((kind) => [...(kind.extensions || []), ...(kind.mimetypes || [])])
    const input = document.createElement('input')
    input.type = 'file'
    input.multiple = true
    input.accept = accept.join(',')
    input.style.display = 'none'

    input.addEventListener('change', (event) => {
      const files = Array.from(event.target.files || [])
      input.remove()
      if (files.length) this.intake(files)
    })

    document.body.appendChild(input)
    input.click()
  },

  intake(files) {
    const { accepted, rejected } = partition(files, this.kinds(), { byExtension: true })

    if (rejected.length) this.pushEventTo(this.el, 'media_drop_rejected', { files: rejected })
    if (!accepted.length) return

    const payload = { files: accepted.map(({ file, kind }) => ({ kind, filename: file.name })) }

    this.pushEventTo(this.el, 'media_drop', payload, (reply) => {
      ;(reply?.children || []).forEach((child, index) => this.handOver(accepted[index].file, child))
    })
  },

  // The reply comes once its render is patched in, so the children's fields
  // are normally there; a few frames more cover a patch still settling.
  handOver(file, { uid, field, token }, attempt = 0) {
    const trigger = document.getElementById(field)

    if (!trigger) {
      if (attempt < 10) {
        requestAnimationFrame(() => this.handOver(file, { uid, field, token }, attempt + 1))
      } else {
        this.el.dispatchEvent(new CustomEvent('brando:handed-upload-settled', {
          bubbles: true,
          detail: { uid, token, failed: true, unavailable: true },
        }))
      }
      return
    }

    const blockField = this.el.closest('[phx-hook="Brando.BlockField"]')?.id
    trigger.dispatchEvent(new CustomEvent('brando:upload-files', { detail: { files: [file], handover: { uid, token, blockField } } }))
  },
})
