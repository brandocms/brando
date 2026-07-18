/**
 * Direct Cloudflare Stream uploads. The server provisions the tus resource and
 * returns its one-time Location; the browser only PATCHes that URL and never
 * receives the account API token.
 */
import * as tus from 'tus-js-client'

export default (app) => ({
  mounted() {
    this.pendingRequests = new Map()
    this.activeUploads = new Map()

    this.el.addEventListener('input', (event) => {
      event.preventDefault()

      if (event.target instanceof HTMLInputElement && event.target.files) {
        const file = event.target.files[0]
        if (file) this.uploadToCloudflare(file)
      }
    })

    this.handleEvent('video_upload_url_ready', (payload) => {
      this.pendingRequests.get(payload.request_ref)?.resolve(payload)
    })

    this.handleEvent('video_upload_url_error', (payload) => {
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

  async uploadToCloudflare(file) {
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

      const { upload_url, video_id } = response
      const upload = new tus.Upload(file, {
        uploadUrl: upload_url,
        uploadSize: file.size,
        chunkSize: 50 * 1024 * 1024,
        retryDelays: [0, 3000, 5000, 10000, 20000, 60000],
        removeFingerprintOnSuccess: true,
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
      upload.start()
    } catch (error) {
      const message = error.message || 'Upload failed'
      console.error('Cloudflare Stream upload error:', error)
      this.activeUploads.get(requestRef)?.abort()
      this.activeUploads.delete(requestRef)
      this.pushVideoEvent('upload_error', { request_ref: requestRef, filename: file.name, error: message })
      window.BrandoUploads?.externalError?.(requestRef, message)
    }
  },
})
