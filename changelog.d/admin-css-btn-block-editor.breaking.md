- The global `button.primary`, `button.secondary`, `.secondary` and `.tiny` button styles are
  removed, and the block editor, its modals and the rich text editor use `.btn`
  ([#3209](https://github.com/brandocms/brando/pull/3209)).
  In an application's admin screens, change `primary` to `btn btn--primary`, `secondary` to `btn`,
  and `secondary small` and `tiny` to `btn btn--sm`; until then those buttons render unstyled.
  Plain buttons in a `.button-group-vertical` are no longer joined: use `.btn` and lay them out in
  the application's stylesheet.
