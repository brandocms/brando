- **A change event naming no entry field no longer closes the form**. In a
  form with block fields, a change event's `_target` names the field to pass
  to the blocks that read the entry. A name with no atom, a target naming only
  the entry, a path into a string or an index into a struct raised and took
  the form down with its unsaved edits, and `__struct__` was written into the
  blocks' copy of the entry. Such a target now leaves the blocks alone. The
  drawer recovery form likewise ignores a field, schema, path or id that names
  nothing instead of raising.
