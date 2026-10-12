- **An image field's picker offers the whole library.** The picker for a
  field, ref or var lists the images made for its image config, which on an
  upgraded site is often none (a meta image's `images/meta`). "Whole library"
  next to "Set up for this field" lists the rest, and Root and Up at the
  field's folder lead there too. An image made for another config is not
  used as it is: picking it puts a copy in the field's upload path, processed
  into the field's sizes (`Brando.Images.for_config_target/3`), and picking
  the same file again reuses that copy. A pick of several (a gallery) keeps
  to the field's own images.

- **⌘Z (Ctrl+Z) undoes a block move or delete.** Outside a text field, rich
  text or code editor, ⌘Z undoes this editor's last structural change in the
  block editor, newest first: a deleted block comes back as with the
  notice's Undo, and a block moved (by dragging, Move up/down or the
  outline) or children reordered go back where they were. A move into
  another parent is not undone this way. In a text field ⌘Z is still the
  field's own undo of typing.
