- **A provider's refusal of a video upload is reported in words** (#3261).
  `Brando.Uploads.video_upload_error_message/1` showed the raw term of any
  answer it did not know, such as Bunny's response body for a rejected key.
  It now says the provider refused the upload; the answer itself is logged.
