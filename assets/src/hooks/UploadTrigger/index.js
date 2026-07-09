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
 *        data-kind="block_var|block_ref_picture|block_ref_gallery"
 *        data-component-id="..."
 *        data-asset-type="file|image"
 *        data-config-target="..."
 *        data-accept=".pdf,.zip">
 *     <input type="file" class="file-input" />
 *     … canvas …
 *   </div>
 */
export default (app) => ({
  mounted() {
    const input = this.el.querySelector('input[type="file"]')
    this._pendingFiles = []

    if (input) {
      const accept = this.el.dataset.accept
      if (accept) input.setAttribute('accept', accept)

      input.addEventListener('change', (e) => {
        e.stopPropagation()
        if (e.target.files && e.target.files.length > 0) {
          this.intake(Array.from(e.target.files), { viaDrop: false })
        }
        input.value = ''
      })
    }

    this.el.addEventListener('click', (e) => {
      if (e.target.closest('.upload-trigger')) {
        e.stopPropagation()
        if (input) input.click()
        return
      }
      if (e.target.closest('button') || e.target.closest('a')) return
      if (this.el.dataset.clickMode === 'trigger') return
      e.stopPropagation()
      if (input) input.click()
    })

    this.el.addEventListener('dragenter', (e) => {
      e.preventDefault()
      e.stopPropagation()
    })

    this.el.addEventListener('dragover', (e) => {
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
      e.preventDefault()
      e.stopPropagation()
      this.el.classList.remove('dragging')
      if (e.dataTransfer.files && e.dataTransfer.files.length > 0) {
        this.intake(Array.from(e.dataTransfer.files), { viaDrop: true })
      }
    })

    if (this.el.dataset.folderBrowser === 'true') {
      this.handleEvent('b:block_upload_folder_confirmed', ({ upload_name, folder, folder_id }) => {
        if (upload_name !== this.el.id) return
        if (!this._pendingFiles.length) return

        this.storeRecentFolder(folder)
        const files = this._pendingFiles.splice(0)
        this.enqueue(files, { folder, folder_id })
      })
    }
  },

  // The folder browser only opens for DROPPED files (matching the old
  // BlockUpload behavior) — file-dialog selections upload straight to the
  // target's default/config folder.
  intake(files, { viaDrop } = { viaDrop: false }) {
    if (viaDrop && this.el.dataset.folderBrowser === 'true') {
      this._pendingFiles = files
      this.openFolderBrowser(files.length)
    } else {
      this.enqueue(files)
    }
  },

  openFolderBrowser(fileCount) {
    const formRoot = this.el.closest('[data-deliver-topic]')

    if (!formRoot || !formRoot.id) {
      console.warn('[UploadTrigger] no form root for folder browser — uploading to default folder')
      this.enqueue(this._pendingFiles.splice(0))
      return
    }

    this.pushEventTo(`#${CSS.escape(formRoot.id)}`, 'open_block_upload_folder_browser', {
      upload_name: this.el.id,
      config_target: this.el.dataset.configTarget || 'default',
      file_count: fileCount,
      initial_folder: this.lastRecentFolder(),
      recent_folders: this.recentFolders(),
    })
  },

  enqueue(files, extra = {}) {
    const ds = this.el.dataset
    const deliverTopic = ds.deliverTopic || this.el.closest('[data-deliver-topic]')?.dataset.deliverTopic

    if (!deliverTopic) {
      console.error('[UploadTrigger] no deliver_topic found — upload aborted', this.el)
      return
    }

    let path = []
    try {
      path = ds.path ? JSON.parse(ds.path) : []
    } catch (_) {
      path = []
    }

    window.BrandoUploads.enqueue(files, {
      kind: ds.kind,
      component_id: ds.componentId,
      var_key: ds.varKey,
      field: ds.field || null,
      path,
      asset_type: ds.assetType,
      config_target: ds.configTarget || 'default',
      deliver_topic: deliverTopic,
      folder: extra.folder || null,
      folder_id: extra.folder_id || null,
    })
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
