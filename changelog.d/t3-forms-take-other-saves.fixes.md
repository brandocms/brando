- **An open form takes in what another editor saved.** When one tab saved an
  entry, the other tabs with it open kept the form they opened with in every
  field nobody had edited there: a `has_many` multi-select (categories) and
  values the save set itself, such as `publish_at` when publishing. A save
  from one of those tabs then deleted the relation's rows and blanked the
  date, and its recovery copy offered to remove them. Each other form now
  takes the saved values, keeps the fields it has edited and not saved as its
  own edits, and compares its recovery copies with the saved entry.
