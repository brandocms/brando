- **A form with a one-to-one subform holding an image or file opens**.
  The form's automatic preloads loaded a `has_many` subform's own images,
  files and relations, but not those of a cast `has_one` or `belongs_to`
  subform, so the form crashed on open unless its own `query` preloaded the
  field. A cast one-to-one subform is now preloaded the same way.

- **A form or duplicate with a subform whose schema has a block field no
  longer crashes**. The subform's preloads named its block field as an
  association, which raised when the entry was loaded: opening its form,
  duplicating or translating it. Block fields are left out of the subform
  preloads.

- **A processed image lands on its subform row after a row marked for
  deletion**. The form still shows a row marked for deletion, and counts it
  when it numbers the rows, but the image was looked up by a count that
  skipped it, so an image finishing processing for a later row was dropped.

- **A duplicate or translation of an entry gets its own one-to-one subform
  row**. Duplicating an entry, which creating a translation does, copied its
  `has_many` subform rows but took over a cast `has_one` row: the copy got
  the row and the original entry lost it. The row is now copied. A
  `belongs_to` stays shared, as before.

- **A duplicate or translation copies what its subform rows hold**. A copied
  subform row's own subform rows used to move from the original to the copy,
  and its blocks were left behind while the copy kept the original's rendered
  HTML. Its gallery stayed shared, so editing the translation's gallery
  edited the original's. Now, at any depth, a copied row's own rows and
  blocks are copied and its galleries cloned.

- **A duplicate or translation keeps the entry's related entries**. The
  links of an `:entries` relation (`related_entries`) were dropped from the
  copy. A duplicate now links the same entries, with link rows of its own. A
  copy into another language (a translation, or the listing's duplicate and
  translate to a language) links their versions in its language, those of its
  subform rows included, and leaves out an entry that has none yet.
