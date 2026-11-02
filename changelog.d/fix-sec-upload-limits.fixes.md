- An uploaded SVG's size is read without an XML parser, so a file full of unique names no longer adds permanent atoms to the VM.

- A client's file name no longer selects a directory with `slugify_filename: false`, on the server and in direct upload keys.

- Uploads are checked again once their bytes arrive: real size, name and contents, not only what the client declared. An image or local video whose contents are not an allowed type is refused, as is an SVG whose name, type and contents disagree.

- An SVG uploaded directly to the bucket is stored instead of failing at the end of the upload.

- The image editor's "save as new copy" now applies the field's size limit and allowed types, and a refused type shows the editor an error instead of crashing the form.

- Replacing a video's file checks its contents, so bytes that are not a video can no longer take its place.
