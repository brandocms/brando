- **A video uploaded in a field's video picker is set on the field**. The
  picker hands an uploaded video to its field as a `select_video` update,
  which the video field, video and gallery blocks, galleries and block vars had
  no clause for: the entry form crashed and the upload was left unselected. A
  gallery var also took a video added from a URL as its single video rather
  than adding it to the gallery.

- **A provider's thumbnail is used only once its video is ready**.
  `Brando.Videos.Helpers.thumbnail_url/1` returned the provider's thumbnail
  URL while the video was still encoding, a broken image in the picker. A
  thumbnail image set on the video is still used at any time.
