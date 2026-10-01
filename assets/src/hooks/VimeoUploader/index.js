/**
 * Direct Vimeo uploads. The server creates the video with the API's tus
 * approach and returns its one-time `upload_link`; the browser only PATCHes
 * that URL and never receives the account access token.
 *
 * Queueing, correlation and teardown live in providerVideoUploader — this file
 * only knows how to move bytes to Vimeo.
 */
import * as tus from 'tus-js-client'
import providerVideoUploader from '../shared/providerVideoUploader'

export default providerVideoUploader({
  label: 'Vimeo',
  startTransfer({ file, response, onProgress, onSuccess, onError }) {
    const upload = new tus.Upload(file, {
      uploadUrl: response.upload_url,
      uploadSize: file.size,
      chunkSize: 128 * 1024 * 1024,
      retryDelays: [0, 3000, 5000, 10000, 20000, 60000],
      removeFingerprintOnSuccess: true,
      onError,
      onProgress,
      onSuccess,
    })

    upload.start()

    return upload
  },
})
