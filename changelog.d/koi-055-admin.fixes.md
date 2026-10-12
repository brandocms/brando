- **Palette swatches in a select stay inside the field.** The 22px
  `.circle.tiny` swatches kept the overlap meant for 40px circles, so a stack
  of them in a palette select's label had a negative width: it spilled out of
  the field over the label, and took a line of its own in the options dialog.
  Tiny circles in a `.circle-stack` overlap by half their width, and a stack
  in a select label or option is inline. Sites that worked around it in their
  own admin CSS can drop the override.
