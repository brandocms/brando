/**
 * Shared machinery for browser-to-provider video uploads (Mux, Bunny,
 * Cloudflare).
 *
 * Every provider follows the same shape: ask the server for a one-time upload
 * destination correlated by `request_ref`, transfer the bytes directly, and
 * report progress/completion/errors back to the owning component. Only the
 * transfer itself differs, so providers supply `startTransfer` and inherit the
 * queue, correlation and teardown from here.
 *
 * Files arrive from three places, all funnelled through `enqueueFiles`:
 *
 * - the hook element's own `<input type="file">` (the "Pick videos" button),
 * - a `brando:enqueue-videos` DOM event carrying `detail.files` — used by
 *   `Brando.TransformerUploader` when a mixed drop is split by media type,
 * - `detail.refs`, an optional parallel array of caller-owned refs. When given,
 *   the ref is used as the `request_ref` so the caller can correlate a file it
 *   already registered server-side with the upload that follows.
 *
 * Transfers run one at a time. Video files are large and each one costs a
 * server round-trip to provision, so a dropped batch of ten uploads in filename
 * order rather than saturating the connection.
 */

const MIME_BY_EXTENSION = {
  mp4: 'video/mp4',
  webm: 'video/webm',
  mov: 'video/quicktime',
  avi: 'video/x-msvideo',
  ogv: 'video/ogg',
}

export default function providerVideoUploader({ label, startTransfer }) {
  return (app) => ({
    mounted() {
      this.pendingRequests = new Map()
      this.activeUploads = new Map()
      this.queue = []
      this.transferring = false

      this.el.addEventListener('input', (event) => {
        event.preventDefault()

        if (event.target instanceof HTMLInputElement && event.target.files) {
          this.enqueueFiles(Array.from(event.target.files))
          event.target.value = ''
        }
      })

      this._onEnqueueVideos = (event) => {
        this.enqueueFiles(event.detail?.files || [], event.detail?.refs || [])
      }
      this.el.addEventListener('brando:enqueue-videos', this._onEnqueueVideos)

      this._onAbortVideo = (event) => this.abortRef(event.detail?.ref)
      this.el.addEventListener('brando:abort-video', this._onAbortVideo)

      this.handleEvent('video_upload_url_ready', (payload) => {
        this.pendingRequests.get(payload.request_ref)?.resolve(payload)
      })

      this.handleEvent('video_upload_url_error', (payload) => {
        console.error('Video upload URL error:', payload)
        this.pendingRequests.get(payload.request_ref)?.resolve(payload)
      })
    },

    destroyed() {
      this.el.removeEventListener('brando:enqueue-videos', this._onEnqueueVideos)
      this.el.removeEventListener('brando:abort-video', this._onAbortVideo)
      this.queue = []

      this.pendingRequests.forEach(({ reject }, requestRef) => {
        reject(new Error('Upload aborted'))
        window.BrandoUploads?.externalError?.(requestRef, 'Upload aborted')
      })
      this.pendingRequests.clear()

      this.activeUploads.forEach((upload, requestRef) => {
        upload.abort()
        window.BrandoUploads?.externalError?.(requestRef, 'Upload aborted')
      })
      this.activeUploads.clear()
    },

    pushVideoEvent(event, payload) {
      const target = this.el.dataset.target
      if (target) {
        this.pushEventTo(target, event, payload)
      } else {
        this.pushEvent(event, payload)
      }
    },

    enqueueFiles(files, refs = []) {
      files.forEach((file, index) => {
        this.queue.push({ file, requestRef: refs[index] || this.requestRef() })
      })
      this.pump()
    },

    // Drop a queued file, or abort one already in flight. The owning component
    // has removed its placeholder, so nothing downstream is expecting it.
    abortRef(requestRef) {
      if (!requestRef) return

      this.queue = this.queue.filter((queued) => queued.requestRef !== requestRef)

      const upload = this.activeUploads.get(requestRef)
      if (upload) {
        upload.abort()
        this.activeUploads.delete(requestRef)
        window.BrandoUploads?.externalError?.(requestRef, 'Upload aborted')
      }

      this.pendingRequests.get(requestRef)?.reject(new Error('Upload aborted'))
    },

    pump() {
      if (this.transferring || !this.queue.length) return

      const { file, requestRef } = this.queue.shift()
      this.transferring = true

      this.uploadFile(file, requestRef).finally(() => {
        this.transferring = false
        this.pump()
      })
    },

    requestRef() {
      const id = window.crypto?.randomUUID?.() || Math.random().toString(36).slice(2, 14)
      return `video-${id}`
    },

    mimeType(file) {
      if (file.type) return file.type
      const extension = file.name.split('.').pop()?.toLowerCase()
      return MIME_BY_EXTENSION[extension] || 'application/octet-stream'
    },

    waitForUploadUrl(requestRef, timeoutMs = 30000) {
      return new Promise((resolve, reject) => {
        const timer = setTimeout(
          () => reject(new Error('Timed out waiting for upload credentials')),
          timeoutMs
        )

        this.pendingRequests.set(requestRef, {
          resolve: (payload) => {
            clearTimeout(timer)
            resolve(payload)
          },
          reject: (error) => {
            clearTimeout(timer)
            reject(error)
          },
        })
      }).finally(() => this.pendingRequests.delete(requestRef))
    },

    reportProgress(requestRef, videoId, bytesUploaded, bytesTotal) {
      const percentage = Math.round((bytesUploaded / bytesTotal) * 100)

      this.pushVideoEvent('video_upload_progress', {
        request_ref: requestRef,
        video_id: videoId,
        uploaded_mb: (bytesUploaded / 1024 / 1024).toFixed(1),
        total_mb: (bytesTotal / 1024 / 1024).toFixed(1),
        percentage,
      })
      window.BrandoUploads?.externalProgress?.(requestRef, percentage)
    },

    reportSuccess(requestRef, videoId) {
      this.activeUploads.delete(requestRef)
      this.pushVideoEvent('video_upload_complete', { request_ref: requestRef, video_id: videoId })
      window.BrandoUploads?.externalComplete?.(requestRef)
    },

    reportError(requestRef, file, error) {
      const message = (typeof error === 'string' && error) || error?.message || 'Upload failed'
      this.activeUploads.delete(requestRef)
      this.pushVideoEvent('upload_error', {
        request_ref: requestRef,
        filename: file.name,
        error: message,
      })
      window.BrandoUploads?.externalError?.(requestRef, message)
    },

    // Resolves when the transfer settles either way — the queue only cares that
    // this file is done occupying the slot, not whether it succeeded.
    async uploadFile(file, requestRef) {
      window.BrandoUploads?.trackExternal?.(file.name, file.size, requestRef)

      try {
        const urlPromise = this.waitForUploadUrl(requestRef)
        this.pushVideoEvent('get_video_upload_url', {
          request_ref: requestRef,
          filename: file.name,
          size: file.size,
          mime_type: this.mimeType(file),
        })
        const response = await urlPromise

        if (response.error) throw new Error(response.error)

        const videoId = response.video_id

        await new Promise((resolve) => {
          const settle = (fn) => (...args) => {
            fn(...args)
            resolve()
          }

          const upload = startTransfer.call(this, {
            file,
            requestRef,
            response,
            onProgress: (bytesUploaded, bytesTotal) =>
              this.reportProgress(requestRef, videoId, bytesUploaded, bytesTotal),
            onSuccess: settle(() => this.reportSuccess(requestRef, videoId)),
            onError: settle((error) => this.reportError(requestRef, file, error)),
          })

          this.activeUploads.set(requestRef, upload)
        })
      } catch (error) {
        console.error(`${label} upload error:`, error)
        this.activeUploads.get(requestRef)?.abort()
        this.reportError(requestRef, file, error)
      }
    },
  })
}
