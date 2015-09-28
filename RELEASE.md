# Release Instructions

  1. Bump version in CHANGELOG
  2. Bump version in mix.exs
  3. Bump version in README.md installation instructions (if we add to hex)
  4. Copy updated villain/ dist files
     cp ~/dev/js/villain/dist/*.* priv/install/templates/static/villain
  5. Run tests, commit, push branch and tags
  6. Merge git-flow to release in tower.
  7. (Push package and docs to hex)
  8. Bump version in CHANGELOG + -dev
  9. Bump version in mix.exs + -dev