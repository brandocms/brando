- `mix brando.migrate54` removes listing actions that repeat the built-in edit, duplicate and delete,
  which showed twice in each row menu ([#3167](https://github.com/brandocms/brando/pull/3167)).
  Check the listings the task's notice names with file and line: those have options beyond `label`,
  `event` and `confirm` and are kept.
