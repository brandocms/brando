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
  async mounted() {
    this.uploadTargetName = this.el.dataset.uploadTarget || 'video'

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

  async uploadToMux(file) {
    try {
      // Store file for when we get the response
      this.pendingFile = file

      // Create promise for async upload URL response
      this.uploadUrlPromise = new Promise((resolve, reject) => {
        this.resolveUploadUrl = resolve
        this.rejectUploadUrl = reject
      })

      // Request upload URL from server
      this.pushEvent('get_video_upload_url', {
        filename: file.name
      })

      // Wait for server to push event back
      const response = await this.uploadUrlPromise

      if (response.error) {
        console.error('Failed to get upload URL:', response.error)
        this.pushEvent('upload_error', {
          filename: file.name,
          error: response.error
        })
        return
      }

      const { upload_url, video_id } = response

      // Upload using UpChunk for chunked upload with progress
      const upload = UpChunk.createUpload({
        endpoint: upload_url,
        file: file,
        chunkSize: 15360 // 15MB chunks
      })

      // Handle progress updates
      upload.on('progress', (progressEvent) => {
        const percentage = Math.round(progressEvent.detail || 0)
        const totalMB = (file.size / 1024 / 1024).toFixed(1)
        const uploadedMB = ((percentage / 100) * file.size / 1024 / 1024).toFixed(1)

        this.pushEvent('video_upload_progress', {
          video_id: video_id,
          uploaded_mb: uploadedMB,
          total_mb: totalMB,
          percentage: percentage
        })
      })

      // Handle successful upload
      upload.on('success', () => {
        this.pushEvent('video_upload_complete', { video_id })
      })

      // Handle upload errors
      upload.on('error', (error) => {
        console.error('UpChunk upload error:', error.detail)
        this.pushEvent('upload_error', {
          filename: file.name,
          error: error.detail?.message || 'Upload failed'
        })
      })

    } catch (error) {
      console.error('Mux upload error:', error)
      this.pushEvent('upload_error', {
        filename: file.name,
        error: error.message
      })
    }
  }
})
