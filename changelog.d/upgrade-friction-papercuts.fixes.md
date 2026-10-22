- The admin search no longer crashes on the first search after the server starts in development, and
  an empty search index says so, with a link to Utilities → Search index
  ([#3161](https://github.com/brandocms/brando/pull/3161)).

- Text variables that hold only an address (`#content`, `/about`, `https://…`) are no longer indexed
  for search ([#3161](https://github.com/brandocms/brando/pull/3161)).
  Rebuild the search index to drop them from existing documents.

- A listing's sort menu reads "Manual order" or "Custom order" when the rows are in an order none of
  its sorts names ([#3161](https://github.com/brandocms/brando/pull/3161)).

- Screen readers no longer announce every block as changed or reach a listing's hidden selection
  bar, and block drag handles have an accessible name
  ([#3161](https://github.com/brandocms/brando/pull/3161)).

- In a synchronized translation, a refused block move leaves the order unchanged, and the block menu
  hides Move up, Move down, Duplicate, Copy and Delete
  ([#3161](https://github.com/brandocms/brando/pull/3161)).
