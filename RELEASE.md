# Release Instructions

  1. git-flow: Start release. Tag without "v", e.g. 0.1.0 - NOT v0.1.0!
  2. Bump version in `CHANGELOG`
  3. Bump version in `mix.exs`
  4. Bump version in `package.json`
  5. Bump version in `README.md` installation instructions (if we add to hex)
  6. Update translations:
     `$ mix gettext.extract && mix gettext.merge priv/gettext`
  7. Update brando_villain if neccessary.
  8. Ensure Phoenix dep is latest version in `package.json`
  9. `$ npm run deploy`
  10. `$ npm publish --access=public`
  11. `$ mix test`
  12. Commit with `Prepare X.X.X release`
  13. git-flow: finish release. Tag without "v", e.g. 0.1.0 - NOT v0.1.0!
     - tag message: Release vX.X.X
  14. Switch to master. Push.
  15. Push `X.X.X` tag to `origin`
  16. (Push package and docs to hex)

  17. Switch to develop-branch.
  18. Bump version in CHANGELOG + -dev
  19. Bump version in mix.exs + -dev
  20. Bump version in package.json + -dev  
  21. Commit `develop` with `Start X.X.X development`. Push
