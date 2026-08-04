/**
 * Direct Mux uploads with request-scoped URL correlation and UploadManager
 * visibility. Every request keeps its own resolver and transfer instance so
 * equal filenames and overlapping component uploads cannot cross wires.
 *
 * Queueing, correlation and teardown live in providerVideoUploader — this file
 * only knows how to move bytes to Mux.
 */
import * as UpChunk from '@mux/upchunk'
import providerVideoUploader from '../shared/providerVideoUploader'

export default providerVideoUploader({
  label: 'Mux',
  startTransfer({ file, response, onProgress, onSuccess, onError }) {
    const upload = UpChunk.createUpload({
      endpoint: response.upload_url,
      file,
      chunkSize: 15360,
    })

    // UpChunk reports a percentage, not byte counts.
    upload.on('progress', (event) => {
      const percentage = Math.round(event.detail || 0)
      onProgress((percentage / 100) * file.size, file.size)
    })

    upload.on('success', () => onSuccess())
    upload.on('error', (error) => onError(error.detail?.message || 'Upload failed'))

    return upload
  },
})
