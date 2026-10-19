- `mix brando.check.legacy_conversion` compares each entry's Villain JSON with the blocks the
  upgrade made of it, reports what is missing, and exits with status 1 when anything is (`--strict`
  also fails on extra content) ([#3161](https://github.com/brandocms/brando/pull/3161)).
