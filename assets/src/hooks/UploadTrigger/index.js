import { subscribeToUpload, uploadTargetKey } from '../shared/uploadProgress'

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
 * - data-folder-browser="true": before enqueueing, open the media folder
 *   browser (handled by the form component / ImagePicker). Files are held
 *   until `b:block_upload_folder_confirmed` comes back with this element's id
 *   as upload_name; the chosen folder/folder_id ride along in the target.
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
    this._pendingFiles = []
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
      if (e.target.closest('button')) e.target.closest('details')?.removeAttribute('open')
      if (e.target.closest('.upload-trigger')) {
        e.stopPropagation()
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
      e.stopPropagation()
      const input = this.el.querySelector('input[type="file"]')
      if (input) input.click()
    })

    this.el.addEventListener('dragenter', (e) => {
      if (!Array.from(e.dataTransfer?.types || []).includes('Files')) return
      e.preventDefault()
      e.stopPropagation()
      this.el.classList.add('dragging')
    })

    this.el.addEventListener('dragover', (e) => {
      if (!Array.from(e.dataTransfer?.types || []).includes('Files')) return
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
      if (e.dataTransfer.files && e.dataTransfer.files.length > 0) {
        this.intake(Array.from(e.dataTransfer.files))
      }
    })

    if (this.el.dataset.folderBrowser === 'true') {
      this.handleEvent('b:block_upload_folder_cancelled', ({ upload_name, request_id }) => {
        if (upload_name === this.el.id && request_id === this._pendingRequest) this._pendingFiles = []
      })
      this.handleEvent('b:block_upload_folder_confirmed', ({ upload_name, request_id, folder, folder_id }) => {
        if (upload_name !== this.el.id || request_id !== this._pendingRequest) return
        if (!this._pendingFiles.length) return

        this._confirmedFolder = { folder, folder_id }
        confirmedFolders.set(this.folderContextKey(), this._confirmedFolder)
        if (confirmedFolders.size > 100) confirmedFolders.delete(confirmedFolders.keys().next().value)
        this.storeRecentFolder(folder)
        this.configureInput()
        const files = this._pendingFiles.splice(0)
        this.enqueue(files, { folder, folder_id })
      })
    }
  },

  destroyed() {
    this._unsubscribeProgress?.()
  },

  updated() {
    if (this._folderConfigTarget !== (this.el.dataset.configTarget || 'default')) {
      this._confirmedFolder = null
      this._pendingFiles = []
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
    const confirmed = confirmedFolders.get(this.folderContextKey())
    if (confirmed && (this.el.dataset.configTarget || 'default') === 'default') {
      this.el.querySelectorAll('[data-media-destination]').forEach(label => { label.textContent = confirmed.folder })
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
  intake(files) {
    if (this.el.dataset.uploadEnabled === 'false') {
      this.showProgress({ status: 'error', error: this.el.dataset.uploadUnavailable })
      return
    }
    const configTarget = this.el.dataset.configTarget || 'default'
    if (this.el.dataset.maxFiles === '1' && files.length > 1) {
      this.showProgress({ status: 'error', error: this.el.dataset.singleFileError || 'Choose one file for this field.' })
      return
    }
    this.showProgress(null)

    // A concrete form/ref/var target already owns its destination through its
    // upload config. Ask for a folder only when the target is truly default.
    if (this.el.dataset.folderBrowser === 'true' && configTarget === 'default' && files.some(file => file.type.startsWith('image/'))) {
      this._confirmedFolder = confirmedFolders.get(this.folderContextKey()) || this._confirmedFolder
      if (this._confirmedFolder) {
        this.enqueue(files, this._confirmedFolder)
        return
      }

      this._pendingFiles = files
      this._pendingRequest = crypto.randomUUID()
      this.openFolderBrowser(files)
    } else {
      this.enqueue(files)
    }
  },

  folderContextKey() {
    return `${uploadTargetKey(this.uploadTarget())}:${this.el.dataset.configTarget || "default"}`
  },

  openFolderBrowser(files) {
    const formRoot = this.el.closest('[data-deliver-topic]')

    if (!formRoot || !formRoot.id) {
      this._pendingFiles = []
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
      expected_asset_id: ds.maxFiles === "1" ? (ds.assetId || "none") : null,
      kind: ds.kind, component_id: ds.componentId, var_key: ds.varKey,
      field: ds.field || null, file_id: ds.fileId || null, path,
      asset_type: ds.assetType, config_target: ds.configTarget || 'default',
      deliver_topic: deliverTopic, folder: extra.folder || ds.folder || null, folder_id: extra.folder_id || ds.folderId || null,
    }
  },

  enqueue(files, extra = {}) {
    if (this.el.dataset.allowedTypes) {
      const allowed = this.el.dataset.allowedTypes.split(',')
      const mediaType = file => file.type.startsWith('video/') ? 'video' : file.type.startsWith('image/') ? 'image' : null
      if (files.some(file => !allowed.includes(mediaType(file)))) {
        this.showProgress({ status: 'error', error: 'This gallery does not accept one or more of these files.' })
        return
      }
      for (const file of files) {
        const type = mediaType(file)
        this.enqueueTarget([file], type === 'video' ? {
          asset_type: 'video', config_target: this.el.dataset.videoConfigTarget || 'default',
        } : extra)
      }
      return
    }
    this.enqueueTarget(files, extra)
  },

  enqueueTarget(files, extra = {}) {
    const target = this.uploadTarget(extra)
    if (extra.asset_type) target.asset_type = extra.asset_type
    if (extra.config_target) target.config_target = extra.config_target
    if (!target.deliver_topic) {
      this.showProgress({ status: 'error', error: 'The upload destination is unavailable. Reopen this editor.' })
      return
    }
    window.BrandoUploads.enqueue(files, target)
  },

  subscribeProgress() {
    if (!this.el.querySelector(':scope > .media-field-progress')) return
    this._unsubscribeProgress?.()
    this._unsubscribeProgress = subscribeToUpload(this.uploadTarget(), state => this.showProgress(state))
  },

  showProgress(state) {
    const container = this.el.querySelector(':scope > .media-field-progress')
    if (!container) return
    container.replaceChildren()
    if (!state || state.status === 'done') return
    container.dataset.state = state.status
    const text = document.createElement('span')
    const messages = { queued: 'Waiting to upload…', uploading: 'Uploading', processing: 'Processing…', cancelled: 'Upload cancelled' }
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
