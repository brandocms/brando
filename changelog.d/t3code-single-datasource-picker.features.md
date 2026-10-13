- **Choose a single datasource entry in the block editor.** Single datasources
  now use the existing entry picker, with one choice that can be replaced or
  cleared. Editor and assistant selections use the same stored association.
  Datasources with only a `get` callback remain valid and offer no new picker
  choices. Clearing a selection immediately after another editor chooses it
  also reaches the shared editing state.
