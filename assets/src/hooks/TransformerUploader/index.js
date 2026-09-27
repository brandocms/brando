/**
 * TransformerUploader — single intake for a transformer subform.
 *
 * A transformer accepts two media types that travel by different routes: images
 * and local/S3 videos go through the sticky UploadManager, provider videos
 * (Mux/Bunny/Cloudflare) go straight to the provider. This hook is what lets an
 * editor stop caring about that — drop a mixed pile of files, or pick either
 * kind, and each file is sorted to the right transport.
 *
 * Intake is uniform regardless of gesture:
 *
 *   1. sort the batch by filename, so the resulting entries are in a
 *      predictable order rather than whichever upload happened to finish first
 *   2. reject anything the configured asset types cannot accept, and report
 *      those filenames back so they are visible instead of silently missing
 *   3. register the survivors with the component, which creates one placeholder
 *      card per file, in order, before any bytes move
 *   4. hand each file to its transport, tagged with the ref its placeholder was
 *      registered under
 *
 * One file dropped on an existing entry (anything carrying
 * data-replace-dom-id) replaces that entry's asset instead: it is registered as
 * a replacement for the entry and travels the same way, so the entry keeps its
 * other fields and its place.
 *
 * Expected markup:
 *
 *   <div phx-hook="Brando.TransformerUploader"
 *        data-target="1"
 *        data-image-accept=".jpg,.png"      (absent → no image field)
 *        data-image-max-size="4000000"
 *        data-video-accept=".mp4,.mov"      (absent → no video field)
 *        data-video-max-size="50000000"
 *        data-video-mode="provider|manager|none"
 *        data-video-hook-id="…-video-uploader"
 *        data-component-id="…"
 *        data-config-target="video:My.Schema:video"
 *        data-image-config-target="image:My.Schema:image">
 *     … entries, actions …
 *   </div>
 */
export default (app) => ({
  mounted() {
    this.el.addEventListener('click', (event) => {
      // "Upload new" on an entry: one file from disk replaces that entry's
      // asset, exactly like dropping it on the card.
      const replacer = event.target.closest('[data-pick-replace]')
      if (replacer && this.el.contains(replacer)) {
        event.preventDefault()
        event.stopPropagation()
        this.openPicker(replacer.dataset.pickKind, (files) =>
          this.replace(files[0], replacer.dataset.pickReplace)
        )
        return
      }

      const picker = event.target.closest('[data-pick]')
      if (!picker || !this.el.contains(picker)) return

      event.preventDefault()
      event.stopPropagation()
      this.openPicker(picker.dataset.pick)
    })

    this.el.addEventListener('dragenter', (event) => {
      event.preventDefault()
      event.stopPropagation()
      this.el.classList.add('dragging')
    })

    this.el.addEventListener('dragover', (event) => {
      event.preventDefault()
      event.stopPropagation()
      this.el.classList.add('dragging')
      this.markReplaceTarget(this.replaceTarget(event))
    })

    this.el.addEventListener('dragleave', (event) => {
      event.stopPropagation()
      // Ignore leaves into our own children, or the highlight flickers.
      if (event.relatedTarget && this.el.contains(event.relatedTarget)) return
      this.el.classList.remove('dragging')
      this.markReplaceTarget(null)
    })

    this.el.addEventListener('drop', (event) => {
      event.preventDefault()
      event.stopPropagation()
      this.el.classList.remove('dragging')

      const target = this.replaceTarget(event)
      this.markReplaceTarget(null)

      const files = Array.from(event.dataTransfer?.files || [])
      if (!files.length) return

      // A single file on an entry replaces its asset; a pile of files, or files
      // dropped anywhere else, become new entries.
      if (target && files.length === 1) {
        this.replace(files[0], target.dataset.replaceDomId)
      } else {
        this.intake(files)
      }
    })

    // The card was removed while its transfer was queued or running. Provider
    // transfers are ours to abort; an UploadManager transfer keeps its own ref
    // and is cancelled from the manager drawer instead.
    this.handleEvent('transformer:abort_upload', ({ ref }) => {
      this.videoHook()?.dispatchEvent(new CustomEvent('brando:abort-video', { detail: { ref } }))
    })
  },

  // A hidden input per media type, created on demand. `accept` narrows the OS
  // dialog, but everything still goes through the same validation as a drop —
  // the dialog's filter is a convenience, not a guarantee. With `onPick` the
  // dialog takes one file and hands it over instead of adding entries.
  openPicker(kind, onPick = null) {
    const accept = {
      images: this.imageAccept(),
      videos: this.videoAccept(),
      files: [...this.imageAccept(), ...this.videoAccept()],
    }[kind] || []

    if (!accept.length) return

    const input = document.createElement('input')
    input.type = 'file'
    input.multiple = !onPick
    input.accept = accept.join(',')
    input.style.display = 'none'

    input.addEventListener('change', (event) => {
      const files = Array.from(event.target.files || [])
      if (files.length) onPick ? onPick(files) : this.intake(files)
      input.remove()
    })

    this.el.appendChild(input)
    input.click()
  },

  imageAccept() {
    return (this.el.dataset.imageAccept || '').split(',').filter(Boolean)
  },

  videoAccept() {
    return (this.el.dataset.videoAccept || '').split(',').filter(Boolean)
  },

  maxSize(key) {
    const raw = parseInt(this.el.dataset[key], 10)
    return Number.isFinite(raw) && raw > 0 ? raw : null
  },

  videoHook() {
    const id = this.el.dataset.videoHookId
    return id ? document.getElementById(id) : null
  },

  extension(file) {
    const parts = file.name.split('.')
    return parts.length > 1 ? `.${parts.pop().toLowerCase()}` : ''
  },

  classify(file) {
    const extension = this.extension(file)
    const images = this.imageAccept()
    const videos = this.videoAccept()

    // Extension first: a .mov can arrive with an empty or lying MIME type, and
    // the accept lists are what the server actually validates against.
    if (images.includes(extension)) return 'image'
    if (videos.includes(extension)) return 'video'
    if (file.type.startsWith('image/') && images.length) return 'image'
    if (file.type.startsWith('video/') && videos.length) return 'video'
    return null
  },

  humanSize(bytes) {
    if (bytes >= 1_073_741_824) return `${(bytes / 1_073_741_824).toFixed(1)} GB`
    if (bytes >= 1_048_576) return `${(bytes / 1_048_576).toFixed(1)} MB`
    if (bytes >= 1024) return `${(bytes / 1024).toFixed(1)} KB`
    return `${bytes} bytes`
  },

  ref() {
    const id = window.crypto?.randomUUID?.() || Math.random().toString(36).slice(2, 14)
    return `tf-${id}`.replace(/[^A-Za-z0-9_-]/g, '')
  },

  // The entry under the pointer, if it can take a replacement. Only a drag
  // carrying exactly one file can replace — dragging several highlights
  // nothing, since they would be added as new entries.
  replaceTarget(event) {
    const items = event.dataTransfer?.items
    if (items && items.length !== 1) return null

    const entry = event.target.closest?.('[data-replace-dom-id]')
    return entry && this.el.contains(entry) ? entry : null
  },

  markReplaceTarget(entry) {
    if (this.replaceEntry === entry) return
    this.replaceEntry?.classList.remove('drop-replace')
    this.replaceEntry = entry
    entry?.classList.add('drop-replace')
  },

  // Validated exactly like intake, then registered against the entry rather
  // than as a new placeholder.
  replace(file, domId) {
    const entry = this.validate(file)

    if (entry.rejected) {
      this.pushTo('reject_files', { files: [entry.rejected] })
      return
    }

    this.pushTo('register_replacement', {
      dom_id: domId,
      file: { ref: entry.ref, kind: entry.kind, filename: file.name, size: file.size },
    })

    this.dispatch([entry])
  },

  validate(file) {
    const kind = this.classify(file)
    if (!kind) return { rejected: { filename: file.name, reason: 'Unsupported file type' } }

    const limit = this.maxSize(kind === 'video' ? 'videoMaxSize' : 'imageMaxSize')
    if (limit && file.size > limit) {
      return { rejected: { filename: file.name, reason: `Too large (max ${this.humanSize(limit)})` } }
    }

    return { file, kind, ref: this.ref() }
  },

  intake(files) {
    const accepted = []
    const rejected = []

    files
      .slice()
      .sort((a, b) => a.name.localeCompare(b.name, undefined, { numeric: true }))
      .forEach((file) => {
        const entry = this.validate(file)
        if (entry.rejected) {
          rejected.push(entry.rejected)
        } else {
          accepted.push(entry)
        }
      })

    if (rejected.length) this.pushTo('reject_files', { files: rejected })
    if (!accepted.length) return

    this.pushTo('register_batch', {
      files: accepted.map(({ file, kind, ref }) => ({
        ref,
        kind,
        filename: file.name,
        size: file.size,
      })),
    })

    this.dispatch(accepted)
  },

  // Placeholders are registered in one push above, so by the time these run the
  // component already knows every ref in the batch.
  dispatch(accepted) {
    const images = accepted.filter((entry) => entry.kind === 'image')
    const videos = accepted.filter((entry) => entry.kind === 'video')

    // Images always ride the sticky UploadManager. A component-local
    // allow_upload cannot work here: LiveView routes upload progress by the
    // file input's *form* owner, and this component necessarily lives inside
    // the entry form, which belongs to the Form component.
    images.forEach((entry) => this.enqueueToManager(entry, 'transformer_image', 'image'))

    if (!videos.length) return

    if (this.el.dataset.videoMode === 'provider') {
      this.videoHook()?.dispatchEvent(
        new CustomEvent('brando:enqueue-videos', {
          detail: {
            files: videos.map((entry) => entry.file),
            refs: videos.map((entry) => entry.ref),
          },
        })
      )
    } else {
      videos.forEach((entry) => this.enqueueToManager(entry, 'transformer_video', 'video'))
    }
  },

  // The ref travels in the target descriptor so the delivery can be correlated
  // back to the placeholder this file already has on screen.
  enqueueToManager({ file, ref }, kind, assetType) {
    const deliverTopic = this.el.closest('[data-deliver-topic]')?.dataset.deliverTopic

    if (!deliverTopic) {
      console.error('[TransformerUploader] no deliver_topic found — upload aborted', this.el)
      return
    }

    const configTarget =
      assetType === 'image' ? this.el.dataset.imageConfigTarget : this.el.dataset.configTarget

    window.BrandoUploads.enqueue([file], {
      kind,
      component_id: this.el.dataset.componentId,
      asset_type: assetType,
      config_target: configTarget || 'default',
      deliver_topic: deliverTopic,
      path: [],
      ref,
    })
  },

  pushTo(event, payload) {
    const target = this.el.dataset.target
    if (target) {
      this.pushEventTo(target, event, payload)
    } else {
      this.pushEvent(event, payload)
    }
  },
})
