- **An image field's picker offers the whole library.** The picker for a
  field, ref or var lists the images made for its image config, which on an
  upgraded site is often none (a meta image's `images/meta`). "Whole library"
  next to "Set up for this field" lists the rest, and Root and Up at the
  field's folder lead there too. An image made for another config is not
  used as it is: picking it puts a copy in the field's upload path, processed
  into the field's sizes (`Brando.Images.for_config_target/3`), and picking
  the same file again reuses that copy. A pick of several (a gallery) keeps
  to the field's own images.
