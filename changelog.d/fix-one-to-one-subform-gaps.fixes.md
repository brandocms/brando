- **A form with a one-to-one subform holding an image or file opens**.
  The form's automatic preloads loaded a `has_many` subform's own images,
  files and relations, but not those of a cast `has_one` or `belongs_to`
  subform, so the form crashed on open unless its own `query` preloaded the
  field. A cast one-to-one subform is now preloaded the same way.

- **A processed image lands on its subform row after a row marked for
  deletion**. The form still shows a row marked for deletion, and counts it
  when it numbers the rows, but the image was looked up by a count that
  skipped it, so an image finishing processing for a later row was dropped.

- **A duplicate or translation of an entry gets its own one-to-one subform
  row**. Duplicating an entry, which creating a translation does, copied its
  `has_many` subform rows but took over a cast `has_one` row: the copy got
  the row and the original entry lost it. The row is now copied. A
  `belongs_to` stays shared, as before.
