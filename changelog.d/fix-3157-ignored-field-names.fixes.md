- **No extra, empty subform row after removing one above date or media fields**
  (#3157). A subform row's inputs are named by position. After a row above it
  was removed, its date and datetime fields (whose input sits in Flatpickr's
  ignored subtree) and its image and video fields (whose component kept the
  first name it was given) still named the old position, and the next change
  sent them as an extra row. They now follow the row's position like its other
  inputs.
