- **A push costs less of `mix check`.** The tests of the repository's own
  shell tooling run only when the branch or working tree changes a file they
  exercise, which took about 90 seconds off a `--fast` check of a `lib/`
  change. The pre-push hook records the tree its check last passed on, and a
  later push from a clean tree that changes only changelog fragments or
  Markdown no gate reads runs just the changelog check. Changelog fragments
  leave the PR number out: `scripts/changelog collate` adds `(#N)` after each
  bold lead without one, from the merge that brought the fragment in, so a PR
  no longer needs a second commit for its number. `mix gettext.extract` no
  longer leaves an untracked template under `test/fixtures/menu_gettext`.
