/**
 * UploadManager — hook mounted on the sticky BrandoAdmin.UploadManager LiveView.
 *
 * Registers the global `window.BrandoUploads` bridge that UploadTrigger hooks
 * (and programmatic callers) use to hand File objects into the manager:
 *
 *   window.BrandoUploads.enqueue(files, target)
 *
 * The bridge shim is registered at module scope (import time) so calls that
 * happen before the manager hook mounts are buffered and flushed on mount.
 *
 * Flow per enqueue:
 *   1. pushEvent("intake") with file metadata + target → server replies with
 *      a decision per file ({ref, transport} or {error}).
 *   2. Accepted files are renamed to "<ref>::<name>" (entry↔item matching,
 *      see docs/UPLOADER.md §5.1) and pushed into the manager's own
 *      allow_upload(:queue) via this.upload().
 */

if (!window.BrandoUploads) {
  window.BrandoUploads = {
    _hook: null,
    _buffer: [],

    enqueue(files, target) {
      const fileList = Array.from(files)
      if (!fileList.length) return

      if (this._hook) {
        this._hook.enqueueFiles(fileList, target)
      } else {
        this._buffer.push([fileList, target])
      }
    },

    _attach(hook) {
      this._hook = hook
      const buffered = this._buffer.splice(0)
      buffered.forEach(([files, target]) => hook.enqueueFiles(files, target))
    },

    _detach(hook) {
      if (this._hook === hook) this._hook = null
    },

    // External transports (Mux/Bunny provider hooks) — track in the drawer for
    // visibility. Returns a ref, or null when the manager isn't mounted
    // (callers must guard).
    trackExternal(filename, size) {
      if (!this._hook) return null
      const ref = `ext-${Math.random().toString(36).slice(2, 10)}`
      this._hook.pushEvent('external_track', { ref, filename, size: size || 0 })
      return ref
    },

    externalProgress(ref, progress) {
      if (ref && this._hook) this._hook.pushEvent('external_progress', { ref, progress: Math.round(progress) })
    },

    externalComplete(ref) {
      if (ref && this._hook) this._hook.pushEvent('external_complete', { ref })
    },

    externalError(ref, message) {
      if (ref && this._hook) this._hook.pushEvent('external_error', { ref, message })
    },
  }
}

export default (app) => ({
  mounted() {
    this._directXhrs = {}

    // Transfer scheduler — at most maxConcurrentTransfers files move at once
    // (config :brando, Brando.Uploads, max_concurrent_transfers: N). Applies
    // to both server uploads and direct PUTs. Server slots are released by
    // the LV pushing b:uploads:released when it consumes an entry; direct
    // slots release locally.
    this._maxTransfers = Math.max(1, parseInt(this.el.dataset.maxConcurrentTransfers || '3', 10) || 3)
    this._transferQueue = []
    this._activeTransfers = new Set()

    this.handleEvent('b:uploads:released', ({ ref }) => this.releaseSlot(ref))

    this.handleEvent('b:uploads:cancel', ({ ref }) => {
      this._transferQueue = this._transferQueue.filter((task) => task.ref !== ref)
      const xhr = this._directXhrs[ref]
      if (xhr) {
        xhr.abort()
        delete this._directXhrs[ref]
      }
      this.releaseSlot(ref)
    })

    window.BrandoUploads._attach(this)
  },

  destroyed() {
    Object.values(this._directXhrs).forEach((xhr) => xhr.abort())
    this._directXhrs = {}
    this._transferQueue = []
    this._activeTransfers = new Set()
    window.BrandoUploads._detach(this)
  },

  enqueueFiles(files, target) {
    const fileMetas = files.map((file, index) => ({
      index,
      name: file.name,
      size: file.size,
      type: file.type,
    }))

    this.pushEvent('intake', { files: fileMetas, target }, (reply) => {
      if (!reply || !reply.decisions) return

      reply.decisions.forEach((decision) => {
        if (decision.error) {
          console.warn(`[UploadManager] rejected "${files[decision.index]?.name}": ${decision.error}`)
          return
        }

        const file = files[decision.index]
        if (!file) return

        if (decision.transport === 'direct') {
          this.scheduleTransfer({ ref: decision.ref, kind: 'direct', file, decision })
        } else {
          const tagged = new File([file], `${decision.ref}::${file.name}`, { type: file.type })
          this.scheduleTransfer({ ref: decision.ref, kind: 'server', file: tagged })
        }
      })
    })
  },

  scheduleTransfer(task) {
    this._transferQueue.push(task)
    this.pumpTransfers()
  },

  pumpTransfers() {
    while (this._activeTransfers.size < this._maxTransfers && this._transferQueue.length > 0) {
      const task = this._transferQueue.shift()
      this._activeTransfers.add(task.ref)

      if (task.kind === 'server') {
        this.upload('queue', [task.file])
      } else {
        this.directUpload(task.file, task.decision)
      }
    }
  },

  releaseSlot(ref) {
    if (this._activeTransfers.delete(ref)) {
      this.pumpTransfers()
    }
  },

  // Client-direct transport: PUT the bytes straight to the presigned URL.
  // Only Content-Type rides along — it is not part of the presign signature,
  // and the acl is a signed query param, so no custom-header CORS surface.
  directUpload(file, decision) {
    const { ref, upload_url } = decision
    const xhr = new XMLHttpRequest()
    this._directXhrs[ref] = xhr

    xhr.upload.addEventListener('progress', (e) => {
      if (e.lengthComputable) {
        this.pushEvent('direct_progress', { ref, progress: Math.round((e.loaded / e.total) * 100) })
      }
    })

    xhr.addEventListener('load', () => {
      delete this._directXhrs[ref]
      this.releaseSlot(ref)
      if (xhr.status >= 200 && xhr.status < 300) {
        this.pushEvent('direct_complete', { ref })
      } else {
        this.pushEvent('direct_error', { ref, message: `Upload failed (HTTP ${xhr.status})` })
      }
    })

    xhr.addEventListener('error', () => {
      delete this._directXhrs[ref]
      this.releaseSlot(ref)
      this.pushEvent('direct_error', { ref, message: 'Upload failed (network or bucket CORS error)' })
    })

    xhr.addEventListener('abort', () => {
      delete this._directXhrs[ref]
      this.releaseSlot(ref)
    })

    xhr.open('PUT', upload_url)
    xhr.setRequestHeader('Content-Type', file.type || 'application/octet-stream')
    xhr.send(file)
  },
})
