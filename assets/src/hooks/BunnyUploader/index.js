/**
 * BunnyUploader Hook
 *
 * Handles direct upload to Bunny Stream for video files using TUS resumable uploads.
 * This hook is used for video assets with upload_strategy: :bunny
 *
 * Events sent to server:
 * - get_video_upload_url: Request upload credentials from server
 * - video_upload_progress: Progress updates during upload
 * - video_upload_complete: Upload finished successfully
 * - upload_error: Upload failed
 *
 * Events received from server:
 * - video_upload_url_ready: Server provides TUS auth credentials
 * - video_upload_url_error: Server failed to get upload credentials
 */
import * as tus from 'tus-js-client'

export default (app) => ({
  currentUpload: null,

  async mounted() {
    this.uploadTargetName = this.el.dataset.uploadTarget || 'video'

    // File selection handler
    this.el.addEventListener('input', async (event) => {
      event.preventDefault()

      if (event.target instanceof HTMLInputElement && event.target.files) {
        const file = event.target.files[0]
        if (file) {
          this.uploadToBunny(file)
        }
      }
    })

    // Listen for video upload URL response from server
    this.handleEvent('video_upload_url_ready', ({ upload_url, video_id, tus_auth, filename }) => {
      if (this.resolveUploadUrl && this.pendingFile && this.pendingFile.name === filename) {
        this.resolveUploadUrl({ upload_url, video_id, tus_auth })
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

  async uploadToBunny(file) {
    try {
      // Store file for when we get the response
      this.pendingFile = file

      // Create promise for async upload URL response
      this.uploadUrlPromise = new Promise((resolve, reject) => {
        this.resolveUploadUrl = resolve
        this.rejectUploadUrl = reject
      })

      // Request upload credentials from server
      this.pushEvent('get_video_upload_url', {
        filename: file.name
      })

      // Wait for server to push event back
      const response = await this.uploadUrlPromise

      if (response.error) {
        console.error('Failed to get upload credentials:', response.error)
        this.pushEvent('upload_error', {
          filename: file.name,
          error: response.error
        })
        return
      }

      const { upload_url, video_id, tus_auth } = response

      // Surface this upload in the sticky UploadManager drawer (visibility only)
      const trackRef = window.BrandoUploads?.trackExternal?.(file.name, file.size)
      this._trackRef = trackRef

      // Create TUS upload with resumable support
      this.currentUpload = new tus.Upload(file, {
        endpoint: upload_url,
        retryDelays: [0, 3000, 5000, 10000, 20000, 60000, 60000],
        headers: {
          'AuthorizationSignature': tus_auth.signature,
          'AuthorizationExpire': tus_auth.expire_time.toString(),
          'VideoId': tus_auth.video_id,
          'LibraryId': tus_auth.library_id.toString()
        },
        metadata: {
          filetype: file.type,
          title: file.name
        },
        onError: (error) => {
          console.error('TUS upload error:', error)
          this.pushEvent('upload_error', {
            filename: file.name,
            error: error.message || 'Upload failed'
          })
          window.BrandoUploads?.externalError?.(trackRef, error.message || 'Upload failed')
          this.currentUpload = null
        },
        onProgress: (bytesUploaded, bytesTotal) => {
          const percentage = Math.round((bytesUploaded / bytesTotal) * 100)
          const totalMB = (bytesTotal / 1024 / 1024).toFixed(1)
          const uploadedMB = (bytesUploaded / 1024 / 1024).toFixed(1)

          this.pushEvent('video_upload_progress', {
            video_id: video_id,
            uploaded_mb: uploadedMB,
            total_mb: totalMB,
            percentage: percentage
          })
          window.BrandoUploads?.externalProgress?.(trackRef, percentage)
        },
        onSuccess: () => {
          this.currentUpload = null
          this.pushEvent('video_upload_complete', { video_id })
          window.BrandoUploads?.externalComplete?.(trackRef)
        }
      })

      // Check for previous uploads to resume
      this.currentUpload.findPreviousUploads().then((previousUploads) => {
        if (previousUploads.length) {
          console.log('Resuming previous Bunny upload...')
          this.currentUpload.resumeFromPreviousUpload(previousUploads[0])
        }
        // Start the upload
        this.currentUpload.start()
      })

    } catch (error) {
      console.error('Bunny upload error:', error)
      this.pushEvent('upload_error', {
        filename: file.name,
        error: error.message
      })
      this.currentUpload = null
    }
  }
})
