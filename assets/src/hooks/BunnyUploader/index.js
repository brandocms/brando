/**
 * Direct Bunny Stream TUS uploads with request-scoped credential correlation.
 */
import * as tus from 'tus-js-client'

export default (app) => ({
  async mounted() {
    this.pendingRequests = new Map()
    this.activeUploads = new Map()

    this.el.addEventListener('input', (event) => {
      event.preventDefault()

      if (event.target instanceof HTMLInputElement && event.target.files) {
        const file = event.target.files[0]
        if (file) this.uploadToBunny(file)
      }
    })

    this.handleEvent('video_upload_url_ready', (payload) => {
      this.pendingRequests.get(payload.request_ref)?.resolve(payload)
    })

    this.handleEvent('video_upload_url_error', (payload) => {
      console.error('Video upload URL error:', payload)
      this.pendingRequests.get(payload.request_ref)?.resolve(payload)
    })
  },

  pushVideoEvent(event, payload) {
    const target = this.el.dataset.target
    if (target) {
      this.pushEventTo(target, event, payload)
    } else {
      this.pushEvent(event, payload)
    }
  },

  destroyed() {
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

  requestRef() {
    const id = window.crypto?.randomUUID?.() || Math.random().toString(36).slice(2, 14)
    return `video-${id}`
  },

  mimeType(file) {
    if (file.type) return file.type
    const extension = file.name.split('.').pop()?.toLowerCase()
    return {
      mp4: 'video/mp4',
      webm: 'video/webm',
      mov: 'video/quicktime',
      avi: 'video/x-msvideo',
      ogv: 'video/ogg',
    }[extension] || 'application/octet-stream'
  },

  waitForUploadUrl(requestRef, timeoutMs = 30000) {
    return new Promise((resolve, reject) => {
      const timer = setTimeout(() => reject(new Error('Timed out waiting for upload credentials')), timeoutMs)

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

  async uploadToBunny(file) {
    const requestRef = this.requestRef()
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

      const { upload_url, video_id, tus_auth } = response
      const upload = new tus.Upload(file, {
        endpoint: upload_url,
        retryDelays: [0, 3000, 5000, 10000, 20000, 60000, 60000],
        headers: {
          AuthorizationSignature: tus_auth.signature,
          AuthorizationExpire: tus_auth.expire_time.toString(),
          VideoId: tus_auth.video_id,
          LibraryId: tus_auth.library_id.toString(),
        },
        metadata: {
          filetype: this.mimeType(file),
          title: file.name,
        },
        onError: (error) => {
          const message = error.message || 'Upload failed'
          this.activeUploads.delete(requestRef)
          this.pushVideoEvent('upload_error', { request_ref: requestRef, filename: file.name, error: message })
          window.BrandoUploads?.externalError?.(requestRef, message)
        },
        onProgress: (bytesUploaded, bytesTotal) => {
          const percentage = Math.round((bytesUploaded / bytesTotal) * 100)
          const totalMB = (bytesTotal / 1024 / 1024).toFixed(1)
          const uploadedMB = (bytesUploaded / 1024 / 1024).toFixed(1)

          this.pushVideoEvent('video_upload_progress', {
            request_ref: requestRef,
            video_id,
            uploaded_mb: uploadedMB,
            total_mb: totalMB,
            percentage,
          })
          window.BrandoUploads?.externalProgress?.(requestRef, percentage)
        },
        onSuccess: () => {
          this.activeUploads.delete(requestRef)
          this.pushVideoEvent('video_upload_complete', { request_ref: requestRef, video_id })
          window.BrandoUploads?.externalComplete?.(requestRef)
        },
      })
      this.activeUploads.set(requestRef, upload)

      const previousUploads = await upload.findPreviousUploads()
      if (previousUploads.length) upload.resumeFromPreviousUpload(previousUploads[0])
      upload.start()
    } catch (error) {
      const message = error.message || 'Upload failed'
      console.error('Bunny upload error:', error)
      this.activeUploads.get(requestRef)?.abort()
      this.activeUploads.delete(requestRef)
      this.pushVideoEvent('upload_error', { request_ref: requestRef, filename: file.name, error: message })
      window.BrandoUploads?.externalError?.(requestRef, message)
    }
  },
})
