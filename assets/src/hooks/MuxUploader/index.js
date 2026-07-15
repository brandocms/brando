/**
 * MuxUploader Hook
 *
 * Handles direct upload to Mux for video files using UpChunk.
 * This hook is used for video assets with upload_strategy: :mux
 *
 * Events sent to server:
 * - get_video_upload_url: Request upload URL from server
 * - video_upload_progress: Progress updates during upload
 * - video_upload_complete: Upload finished successfully
 * - upload_error: Upload failed
 *
 * Events received from server:
 * - video_upload_url_ready: Server provides upload URL
 * - video_upload_url_error: Server failed to get upload URL
 */
import * as UpChunk from '@mux/upchunk'

export default (app) => ({
  currentUpload: null,

  async mounted() {
    // File selection handler
    this.el.addEventListener('input', async (event) => {
      event.preventDefault()

      if (event.target instanceof HTMLInputElement && event.target.files) {
        const file = event.target.files[0]
        if (file) {
          this.uploadToMux(file)
        }
      }
    })

    // Listen for video upload URL response from server
    this.handleEvent('video_upload_url_ready', ({ upload_url, video_id, filename }) => {
      if (this.resolveUploadUrl && this.pendingFile && this.pendingFile.name === filename) {
        this.resolveUploadUrl({ upload_url, video_id })
      }
    })

    // Listen for video upload URL error from server
    this.handleEvent('video_upload_url_error', ({ error, filename }) => {
      console.error('Video upload URL error:', { error, filename })
      if (this.resolveUploadUrl && this.pendingFile && this.pendingFile.name === filename) {
        this.resolveUploadUrl({ error })
      }
    })
  },

  // Route events to the owning component (video picker / transformer set
  // data-target={@myself}); without a target they go to the form LiveView,
  // which relays to the Form component (the drawer flow).
  pushVideoEvent(event, payload) {
    const target = this.el.dataset.target
    if (target) {
      this.pushEventTo(target, event, payload)
    } else {
      this.pushEvent(event, payload)
    }
  },

  destroyed() {
    // Abort any in-progress upload when hook is destroyed. Tell the manager
    // drawer too — external items have no cancel/dismiss affordance, so a
    // silent abort would pin the item at :uploading forever.
    if (this.currentUpload) {
      this.currentUpload.abort()
      this.currentUpload = null
      window.BrandoUploads?.externalError?.(this._trackRef, 'Upload aborted')
      this._trackRef = null
    }
  },

  // The URL handshake must be able to fail — a server that never answers
  // (or answers for a different filename) would otherwise hang the upload
  // silently forever.
  waitForUploadUrl(timeoutMs = 30000) {
    let timer
    return new Promise((resolve, reject) => {
      this.resolveUploadUrl = resolve
      this.rejectUploadUrl = reject
      timer = setTimeout(() => reject(new Error('Timed out waiting for upload URL')), timeoutMs)
    }).finally(() => {
      clearTimeout(timer)
      this.resolveUploadUrl = null
      this.rejectUploadUrl = null
    })
  },

  async uploadToMux(file) {
    try {
      // Store file for when we get the response
      this.pendingFile = file

      // Request upload URL from server, then wait for the push-back
      const urlPromise = this.waitForUploadUrl()
      this.pushVideoEvent('get_video_upload_url', {
        filename: file.name
      })
      const response = await urlPromise

      if (response.error) {
        console.error('Failed to get upload URL:', response.error)
        this.pushVideoEvent('upload_error', {
          filename: file.name,
          error: response.error
        })
        return
      }

      const { upload_url, video_id } = response

      // Surface this upload in the sticky UploadManager drawer (visibility only)
      const trackRef = window.BrandoUploads?.trackExternal?.(file.name, file.size)
      this._trackRef = trackRef

      // Upload using UpChunk for chunked upload with progress
      const upload = UpChunk.createUpload({
        endpoint: upload_url,
        file: file,
        chunkSize: 15360 // 15MB chunks
      })
      this.currentUpload = upload

      // Handle progress updates
      upload.on('progress', (progressEvent) => {
        const percentage = Math.round(progressEvent.detail || 0)
        const totalMB = (file.size / 1024 / 1024).toFixed(1)
        const uploadedMB = ((percentage / 100) * file.size / 1024 / 1024).toFixed(1)

        this.pushVideoEvent('video_upload_progress', {
          video_id: video_id,
          uploaded_mb: uploadedMB,
          total_mb: totalMB,
          percentage: percentage
        })
        window.BrandoUploads?.externalProgress?.(trackRef, percentage)
      })

      // Handle successful upload
      upload.on('success', () => {
        this.currentUpload = null
        this.pushVideoEvent('video_upload_complete', { video_id })
        window.BrandoUploads?.externalComplete?.(trackRef)
      })

      // Handle upload errors
      upload.on('error', (error) => {
        console.error('UpChunk upload error:', error.detail)
        this.currentUpload = null
        this.pushVideoEvent('upload_error', {
          filename: file.name,
          error: error.detail?.message || 'Upload failed'
        })
        window.BrandoUploads?.externalError?.(trackRef, error.detail?.message || 'Upload failed')
      })

    } catch (error) {
      console.error('Mux upload error:', error)
      this.pushVideoEvent('upload_error', {
        filename: file.name,
        error: error.message
      })
    }
  }
})
