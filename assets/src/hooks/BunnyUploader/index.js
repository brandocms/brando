/**
 * Direct Bunny Stream TUS uploads with request-scoped credential correlation.
 *
 * Queueing, correlation and teardown live in providerVideoUploader — this file
 * only knows how to move bytes to Bunny.
 */
import * as tus from 'tus-js-client'
import providerVideoUploader from '../shared/providerVideoUploader'

export default providerVideoUploader({
  label: 'Bunny',
  startTransfer({ file, response, onProgress, onSuccess, onError }) {
    const { upload_url: uploadUrl, tus_auth: tusAuth } = response

    const upload = new tus.Upload(file, {
      // tus-js-client resolves the upload's Location against the endpoint, and
      // throws on a relative one: a configured path (`tus_endpoint`) is the
      // admin page's.
      endpoint: new URL(uploadUrl, window.location.href).toString(),
      retryDelays: [0, 3000, 5000, 10000, 20000, 60000, 60000],
      headers: {
        AuthorizationSignature: tusAuth.signature,
        AuthorizationExpire: tusAuth.expire_time.toString(),
        VideoId: tusAuth.video_id,
        LibraryId: tusAuth.library_id.toString(),
      },
      metadata: {
        filetype: this.mimeType(file),
        title: file.name,
      },
      onError,
      onProgress,
      onSuccess,
    })

    upload.findPreviousUploads().then((previousUploads) => {
      if (previousUploads.length) upload.resumeFromPreviousUpload(previousUploads[0])
      upload.start()
    })

    return upload
  },
})
