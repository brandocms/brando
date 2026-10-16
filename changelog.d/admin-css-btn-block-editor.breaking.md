- **The global `button.primary`, `button.secondary`, `.secondary` and `.tiny`
  button styles are gone; use `.btn`.** An application's admin screens that
  still write them change `primary` to `btn btn--primary`, `secondary` to
  `btn`, `secondary small` to `btn btn--sm` and `tiny` to `btn btn--sm`.
  Until then those buttons render unstyled. The block editor, its config
  modals and the rich text editor's popover and AI suggestion now use
  `.btn`; the identifier picker's content types are menu rows
  (`.identifier-picker-option`). Plain buttons in a `.button-group-vertical`
  are no longer joined or given a selected look; use `.btn` and lay them out
  in the application's stylesheet. The drawer's `.file-input-button` rule,
  which no screen rendered, is gone.
