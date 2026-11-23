import { subscribeToUpload, uploadTargetKey } from '../shared/uploadProgress'
import { handOver, settle } from '../shared/mediaDropHandover'

// Confirmation belongs to a form target, including its inline and modal views.
const confirmedFolders = new Map()

/**
 * UploadTrigger — drop zone / click-to-upload element for any upload source.
 *
 * Reads its target descriptor from data attributes and forwards selected or
 * dropped files to the sticky UploadManager via window.BrandoUploads.enqueue.
 * The deliver_topic is resolved from the closest ancestor carrying
 * data-deliver-topic (the form component's root element) unless set directly.
 *
 * Optional behaviors:
 * - data-folder-browser="true": an image uploads to the folder chosen for
 *   this field, or the last one used. "Change" (`.media-destination-change`)
 *   opens the media folder browser (the form component / ImagePicker) for the
 *   next uploads; `b:block_upload_folder_confirmed` comes back with this
 *   element's id as upload_name and the chosen folder/folder_id. No files
 *   wait on that choice.
 * - data-click-mode="trigger": only clicks on a `.upload-trigger` element open
 *   the file dialog (for wrappers containing other interactive content).
 *   Default: any click outside buttons/links opens it.
 *
 * Expected markup:
 *
 *   <div phx-hook="Brando.UploadTrigger"
 *        data-kind="block_var|block_var_gallery|block_ref_picture|block_ref_file|block_ref_video|block_ref_gallery|entry_var|entry_var_gallery|entry_field|entry_field_gallery|file_replace"
 *        data-component-id="..."
 *        data-asset-type="file|image|video"
 *        data-config-target="..."
 *        data-accept=".pdf,.zip">
 *     <input type="file" class="file-input" />
 *     … canvas …
 *   </div>
 */
export default (app) => ({
  mounted() {
    this._confirmedFolder = null
    this._folderConfigTarget = this.el.dataset.configTarget || 'default'
    this.configureInput()
    this.subscribeProgress()

    // Delegate from the stable hook root. LiveView may replace the actual
    // file input while patching gallery objects, but `change` still bubbles.
    this._onInputChange = (e) => {
      if (e.target !== this.el.querySelector(':scope > input[type="file"]')) return
      this.handleInputChange(e)
    }
    this.el.addEventListener('change', this._onInputChange)

    this.el.addEventListener('click', (e) => {
      if (e.target.closest('.media-destination-change')) {
        e.preventDefault()
        e.stopPropagation()
        this.changeDestination()
        return
      }
      if (e.target.closest('button')) e.target.closest('details')?.removeAttribute('open')
      if (e.target.closest('.upload-trigger')) {
        e.stopPropagation()
        if (this.sourceLocked()) return
        const input = this.el.querySelector('input[type="file"]')
        if (input) {
          // Arm the current input itself. Nested LiveComponents can replace or
          // retain hook roots in an order where a delegated listener is briefly
          // unavailable; the user-triggered chooser must still always upload.
          input.addEventListener('change', (event) => this.handleInputChange(event), { once: true })
          input.click()
        }
        return
      }
      if (e.target.closest('button') || e.target.closest('a')) return
      if (this.el.dataset.clickMode === 'trigger') return
      if (this.sourceLocked()) return
      e.stopPropagation()
      const input = this.el.querySelector('input[type="file"]')
      if (input) input.click()
    })

    this.el.addEventListener('dragenter', (e) => {
      if (!Array.from(e.dataTransfer?.types || []).includes('Files')) return
      if (this.refuseDrag(e)) return
      e.preventDefault()
      e.stopPropagation()
      this.el.classList.add('dragging')
    })

    this.el.addEventListener('dragover', (e) => {
      if (!Array.from(e.dataTransfer?.types || []).includes('Files')) return
      if (this.refuseDrag(e)) return
      e.preventDefault()
      e.stopPropagation()
      this.el.classList.add('dragging')
    })

    this.el.addEventListener('dragleave', (e) => {
      e.stopPropagation()
      // Ignore leaves into our own children — only clear when actually
      // exiting the drop zone (prevents highlight flicker).
      if (e.relatedTarget && this.el.contains(e.relatedTarget)) return
      this.el.classList.remove('dragging')
    })

    this.el.addEventListener('drop', (e) => {
      if (!e.dataTransfer?.files?.length) return
      e.preventDefault()
      e.stopPropagation()
      this.el.classList.remove('dragging')
      if (this.sourceLocked()) return
      if (e.dataTransfer.files && e.dataTransfer.files.length > 0) {
        this.intake(Array.from(e.dataTransfer.files))
      }
    })

    // Files handed over by another drop target: a multi block's media drop
    // (`MediaDrop`), which made this field's block for them. They upload as
    // a file dropped here does, and the upload started for them says when
    // it settles (`shared/mediaDropHandover`).
    this.el.addEventListener('brando:upload-files', (e) => {
      this.intake(Array.from(e.detail.files), e.detail.handover)
    })

    if (this.el.dataset.folderBrowser === 'true') {
      this.handleEvent('b:block_upload_folder_confirmed', ({ upload_name, request_id, folder, folder_id }) => {
        if (upload_name !== this.el.id || request_id !== this._pendingRequest) return

        this._confirmedFolder = { folder, folder_id }
        confirmedFolders.set(this.folderContextKey(), this._confirmedFolder)
        if (confirmedFolders.size > 100) confirmedFolders.delete(confirmedFolders.keys().next().value)
        this.storeRecentFolder(folder)
        this.configureInput()
      })
    }
  },

  // In a synchronized translation media in blocks follows the source
  // (`.is-source-locked`, Blocks.css): nothing uploads, and a file dragged
  // over the field shows it cannot be dropped.
  sourceLocked() {
    return !!this.el.closest('.is-source-locked')
  },

  refuseDrag(e) {
    if (!this.sourceLocked()) return false
    e.preventDefault()
    e.stopPropagation()
    e.dataTransfer.dropEffect = 'none'
    return true
  },

  destroyed() {
    this._unsubscribeProgress?.()
    this._providerHook?.removeEventListener('brando:video-upload', this._onProviderUpload)
  },

  updated() {
    if (this._folderConfigTarget !== (this.el.dataset.configTarget || 'default')) {
      this._confirmedFolder = null
      this._folderConfigTarget = this.el.dataset.configTarget || 'default'
    }
    this.subscribeProgress()
    // Some nested component patches tear down the DOM listener while keeping
    // the hook instance. Re-attach idempotently on every update.
    this.el.removeEventListener('change', this._onInputChange)
    this.el.addEventListener('change', this._onInputChange)
    this.configureInput()
  },

  configureInput() {
    const destination = confirmedFolders.get(this.folderContextKey())?.folder || this.lastRecentFolder()
    if (destination && this.el.dataset.folderBrowser === 'true' && (this.el.dataset.configTarget || 'default') === 'default') {
      this.el.querySelectorAll('[data-media-destination]').forEach(label => { label.textContent = destination })
    }
    const input = this.el.querySelector(':scope > input[type="file"]')
    if (!input) return

    const accept = this.el.dataset.accept
    if (accept) input.setAttribute('accept', accept)
  },

  handleInputChange(e) {
    e.stopPropagation()
    if (e.target.files && e.target.files.length > 0) {
      this.intake(Array.from(e.target.files))
    }
    e.target.value = ''
  },

  // Folder behavior belongs to the target context, not the input gesture.
  // A click-selected file and a dropped file must therefore follow the same
  // configured-folder/current-folder/default-folder precedence.
  intake(files, handover = null) {
    this._providerState = null
    if (this.el.dataset.uploadEnabled === 'false') {
      this.refuse(this.el.dataset.uploadUnavailable, handover)
      return
    }
    const configTarget = this.el.dataset.configTarget || 'default'
    if (this.el.dataset.maxFiles === '1' && files.length > 1) {
      this.refuse(this.el.dataset.singleFileError || 'Choose one file for this field.', handover)
      return
    }
    this.showProgress(null)

    // A video field whose provider takes the upload itself (Mux, Bunny,
    // Cloudflare, Vimeo) hands the file to the provider's hook, as the video
    // picker does, instead of the upload manager.
    if (this.el.dataset.videoHookId) {
      this.enqueueToProvider(files, handover)
      return
    }

    // A concrete form/ref/var target already owns its destination through its
    // upload config. A default-target image goes straight to the folder chosen
    // for this field, or the last one used, or the config's own; "Change"
    // beside the destination picks another. Uploading does not stop to ask.
    if (this.el.dataset.folderBrowser === 'true' && configTarget === 'default' && files.some(file => file.type.startsWith('image/'))) {
      this.enqueue(files, this.destinationFolder() || {}, handover)
    } else {
      this.enqueue(files, {}, handover)
    }
  },

  // A file this field cannot take: said in the field, and to the drop that
  // handed it over
  refuse(error, handover) {
    this.showProgress({ status: 'error', error })
    if (handover) settle(handover, { failed: true, error })
  },

  destinationFolder() {
    this._confirmedFolder = confirmedFolders.get(this.folderContextKey()) || this._confirmedFolder
    if (this._confirmedFolder) return this._confirmedFolder
    const last = this.lastRecentFolder()
    return last ? { folder: last, folder_id: null } : null
  },

  // "Change": choose the folder for this field's next uploads, with no files
  // waiting.
  changeDestination() {
    this._pendingRequest = crypto.randomUUID()
    this.openFolderBrowser([])
  },

  folderContextKey() {
    return `${uploadTargetKey(this.uploadTarget())}:${this.el.dataset.configTarget || "default"}`
  },

  openFolderBrowser(files) {
    const formRoot = this.el.closest('[data-deliver-topic]')

    if (!formRoot || !formRoot.id) {
      this.showProgress({ status: 'error', error: 'The upload destination is unavailable. Reopen this editor.' })
      return
    }

    this.pushEventTo(`#${CSS.escape(formRoot.id)}`, 'open_block_upload_folder_browser', {
      upload_name: this.el.id,
      request_id: this._pendingRequest,
      config_target: this.el.dataset.configTarget || 'default',
      file_count: files.length,
      video_count: files.filter(file => file.type.startsWith('video/')).length,
      video_config_target: this.el.dataset.videoConfigTarget || 'default',
      target_label: this.el.dataset.uploadLabel || null,
      initial_folder: this.lastRecentFolder(),
      recent_folders: this.recentFolders(),
    })
  },

  uploadTarget(extra = {}) {
    const ds = this.el.dataset
    const deliverTopic = ds.deliverTopic || this.el.closest('[data-deliver-topic]')?.dataset.deliverTopic
    let path = []
    try { path = ds.path ? JSON.parse(ds.path) : [] } catch (_) { /* invalid paths are rejected at intake */ }
    return {
      // A single-asset target's current asset, which the delivery replaces only
      // if it is still shown. The video picker sets it for the target it is open for.
      expected_asset_id: ds.maxFiles === "1" ? (ds.assetId || "none") : (ds.expectedAssetId || null),
      // The video picker's opening, handed back with the delivery
      ref: ds.ref || null,
      kind: ds.kind, component_id: ds.componentId, var_key: ds.varKey,
      field: ds.field || null, file_id: ds.fileId || null, path,
      asset_type: ds.assetType, config_target: ds.configTarget || 'default',
      deliver_topic: deliverTopic, folder: extra.folder || ds.folder || null, folder_id: extra.folder_id || ds.folderId || null,
    }
  },

  enqueue(files, extra = {}, handover = null) {
    if (this.el.dataset.allowedTypes) {
      const allowed = this.el.dataset.allowedTypes.split(',')
      const mediaType = file => file.type.startsWith('video/') ? 'video' : file.type.startsWith('image/') ? 'image' : null
      if (files.some(file => !allowed.includes(mediaType(file)))) {
        this.refuse('This gallery does not accept one or more of these files.', handover)
        return
      }
      for (const file of files) {
        const type = mediaType(file)
        this.enqueueTarget([file], type === 'video' ? {
          asset_type: 'video', config_target: this.el.dataset.videoConfigTarget || 'default',
        } : extra, handover)
      }
      return
    }
    this.enqueueTarget(files, extra, handover)
  },

  enqueueToProvider(files, handover) {
    const hook = document.getElementById(this.el.dataset.videoHookId)
    if (!hook) {
      this.refuse('The upload destination is unavailable. Reopen this editor.', handover)
      return
    }

    const ref = `field-${window.crypto?.randomUUID?.() || Math.random().toString(36).slice(2, 14)}`
    this._providerRef = ref
    if (handover) handOver(ref, handover)

    if (this._providerHook !== hook) {
      this._providerHook?.removeEventListener('brando:video-upload', this._onProviderUpload)
      this._onProviderUpload = ({ detail }) => {
        if (detail.ref !== this._providerRef) return
        const state = detail.status === 'uploading' ? { status: 'uploading', progress: detail.progress } :
          detail.error ? { status: 'error', error: detail.error } : { status: 'done' }
        // Only a failure outlives a patch: a progress the socket never got to
        // finish would otherwise stay on the field
        this._providerState = state.status === 'error' ? { state, assetId: this.el.dataset.assetId } : null
        this.showProgress(state)
      }
      hook.addEventListener('brando:video-upload', this._onProviderUpload)
      this._providerHook = hook
    }

    this.showProgress({ status: 'queued' })
    hook.dispatchEvent(new CustomEvent('brando:enqueue-videos', { detail: { files, refs: [ref] } }))
  },

  enqueueTarget(files, extra = {}, handover = null) {
    const target = this.uploadTarget(extra)
    if (extra.asset_type) target.asset_type = extra.asset_type
    if (extra.config_target) target.config_target = extra.config_target
    if (!target.deliver_topic) {
      this.refuse('The upload destination is unavailable. Reopen this editor.', handover)
      return
    }
    window.BrandoUploads.enqueue(files, target, handover)
  },

  subscribeProgress() {
    if (!this.el.querySelector(':scope > .media-field-progress')) return
    this._unsubscribeProgress?.()
    this._unsubscribeProgress = subscribeToUpload(this.uploadTarget(), state => this.showProgress(state || this.providerState()))
  },

  // What the provider last said of this field's upload, which the upload
  // manager does not hold: shown again after a patch, until the editor
  // uploads again or the field shows another selection
  providerState() {
    if (this._providerState?.assetId !== this.el.dataset.assetId) this._providerState = null
    return this._providerState?.state || null
  },

  showProgress(state) {
    const container = this.el.querySelector(':scope > .media-field-progress')
    if (!container) return
    container.replaceChildren()
    delete container.dataset.state
    if (!state || state.status === 'done') return
    container.dataset.state = state.status
    const text = document.createElement('span')
    const messages = { queued: 'Waiting to upload…', uploading: 'Uploading', processing: this.el.dataset.uploadProcessing || 'Processing…', cancelled: 'Upload cancelled' }
    text.textContent = state.status === 'error' ? state.error :
      state.status === 'uploading' ? `${messages.uploading} · ${state.progress}%` : messages[state.status]
    if (state.total && state.status !== 'error') text.textContent += ` · ${state.completed} of ${state.total} ready${state.failed ? ` · ${state.failed} failed` : ''}`
    container.append(text)
    if (['queued', 'uploading'].includes(state.status)) {
      const progress = document.createElement('progress')
      progress.max = 100
      progress.value = state.progress || 0
      container.append(progress)
    }
  },

  recentFolders() {
    try {
      const value = localStorage.getItem('brando:image_upload:recent_folders')
      const parsed = value ? JSON.parse(value) : []
      return Array.isArray(parsed) ? parsed : []
    } catch (_) {
      return []
    }
  },

  lastRecentFolder() {
    const folders = this.recentFolders()
    return folders.length > 0 ? folders[0] : null
  },

  storeRecentFolder(folder) {
    if (!folder) return
    const recent = [folder, ...this.recentFolders().filter((entry) => entry !== folder)].slice(0, 5)

    try {
      localStorage.setItem('brando:image_upload:recent_folders', JSON.stringify(recent))
    } catch (_) {
      // ignore localStorage failures
    }
  },
})
