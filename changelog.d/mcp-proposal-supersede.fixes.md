- A connected tool's `prepare_proposal` call refines its latest proposal under review when that
  one has problems or changes the same entries, instead of storing another proposal beside it.
  The tool can name the proposal to refine with `replaces`, and the result says which one it
  replaced ([#3715](https://github.com/brandocms/brando/issues/3715)).
