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
