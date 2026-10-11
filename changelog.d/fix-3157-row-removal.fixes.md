- **Subform rows survive edits sent before an add or a removal lands** (#3157).
  A change or Save serialized in the browser before an add or a removal
  reached it listed the rows as they were, and the server rebuilt them from
  it: a removed row could come back, and an added row was lost (clicking
  "Add entry" straight after typing in a row added nothing). The form now
  remembers rows it has added or removed until the browser shows them, and
  corrects only those in the next params before Ecto casts them; ordering,
  drops and validation stay Ecto's `sort_param`/`drop_param`. A subform row's
  hidden inputs now sit inside the row, so none is left behind after a
  removal.
