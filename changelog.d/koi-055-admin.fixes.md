- **Palette swatches in a select stay inside the field.** The 22px
  `.circle.tiny` swatches kept the overlap meant for 40px circles, so a stack
  of them in a palette select's label had a negative width: it spilled out of
  the field over the label, and took a line of its own in the options dialog.
  Tiny circles in a `.circle-stack` overlap by half their width, and a stack
  in a select label or option is inline. Sites that worked around it in their
  own admin CSS can drop the override.

- **The system check's links to Utilities rows say where they go.** The
  sitemap and image config checks linked to their maintenance rows with
  buttons labelled "Generate sitemap" and "Recreate changed images", the
  labels of the buttons on those rows, so clicking one and waiting for the
  action did nothing. They read "Go to sitemap" and "Go to image sizes", and
  the row they lead to is marked. The checks still only read.

- **The image picker's organize selection, drag to folder and selection
  marks work again.** Its list's `phx-viewport-bottom` (rows a page at a
  time) made LiveView mount its own InfiniteScroll hook on the element in
  place of `Brando.ImagePickerGrid`, so the picker's hook never ran. The hook
  sits on a wrapper now.

- **"Use existing" for a re-uploaded file only offers an image made for the
  same field.** `Brando.Images.find_duplicate/1` matched the file alone, so
  uploading a file into a meta image field could put a copy cut to the cover
  field's sizes there, without the size the meta tags render.
