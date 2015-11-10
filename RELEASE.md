# Release Instructions

  1. git-flow: Start release. Tag without "v", e.g. 0.1.0 - NOT v0.1.0!
  2. Bump version in CHANGELOG
  3. Bump version in mix.exs
  4. Bump version in README.md installation instructions (if we add to hex)
  5. Update translations:
     `$ mix gettext.extract && mix gettext.merge priv/gettext`
  6. Copy updated villain/ dist files
     `$ cp ~/dev/js/villain/dist/villain.all.js priv/static/vendor/js`
     `$ cp ~/dev/js/villain/dist/villain.css priv/static/vendor/css`
  7. `$ brunch build`
  8. Run tests
  9. Commit with `Prepare X.X.X release`
  10. git-flow: finish release. Tag without "v", e.g. 0.1.0 - NOT v0.1.0!
     - tag message: Release vX.X.X
  11. Switch to master. Push.
  12. (Push package and docs to hex)
  13. Switch to develop-branch.
  14. Bump version in CHANGELOG + -dev
  15. Bump version in mix.exs + -dev
  16. Commit `develop` with `Start X.X.X development`. Push
  17. Push `X.X.X` tag to `origin`