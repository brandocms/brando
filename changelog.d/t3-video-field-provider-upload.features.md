- **A video field uploads to its provider itself**. A field whose config
  uploads to Mux, Bunny, Cloudflare or Vimeo offered no Upload, and refused a
  dropped file with "Use Select video to upload a video with this provider".
  Upload and a drop now send the file from the browser straight to the
  provider, as the video picker does, with the field's own config, and the
  field takes the video once it is up. Progress shows in the field and the
  upload drawer.
