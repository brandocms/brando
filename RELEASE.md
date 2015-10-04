# Release Instructions

  1. git-flow: Start release. Tag without "v", e.g. 0.1.0 - NOT v0.1.0!
  2. Bump version in CHANGELOG
  3. Bump version in mix.exs
  4. Bump version in README.md installation instructions (if we add to hex)
  5. Copy updated villain/ dist files
     cp ~/dev/js/villain/dist/*.* priv/install/templates/static/villain
  6. Run tests
  7. Commit with `Prepare X.X.X release`
  8. git-flow: finish release. Tag without "v", e.g. 0.1.0 - NOT v0.1.0!
  9. Switch to master. Push.
  9. (Push package and docs to hex)
  10. Switch to develop-branch.
  11. Bump version in CHANGELOG + -dev
  12. Bump version in mix.exs + -dev
  13. Commit `develop` with `Start X.X.X development`. Push
  14. Push `X.X.X` tag to `origin`