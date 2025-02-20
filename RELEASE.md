# Release Instructions

  1. Bump version in `CHANGELOG`
     Bump version in `mix.exs`
     Bump version in `README.md` installation instructions (if we add to hex)
     Bump version in `assets/package.json`
     Bump Brando version in installation template: `priv/templates/brando.install/mix.exs`
  2. Update translations:
     `$ mix gettext.extract && mix gettext.merge priv/gettext`
  3. `$ mix test`
  4. `$ cd e2e/e2e_project && ./test_e2e.sh`
  5.  Commit with `Release X.X.X`
  6.  Tag with `vX.X.X`
  7.  Push `vX.X.X` tag to `origin`
  8.  Bump version in `CHANGELOG` + -dev
  9.  Bump version in `mix.exs` + -dev
  10. Commit with `Start X.X.X development`. Push
