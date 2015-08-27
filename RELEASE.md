# Release Instructions

  1. Bump version in CHANGELOG and mix.exs
  2. Bump version in README.md installation instructions
  3. Copy updated villain/ dist files
     cp ~/dev/js/villain/dist/*.* priv/install/templates/static/villain
  4. Run tests, commit, push branch and tags
  5. Push package and docs to hex
  6. Update CHANGELOG, mix.exs. Bump version and add -dev