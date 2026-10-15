# Release Instructions

Hex `brando`, npm `@brandocms/brandojs` and the Git tag share one version:
`0.55.0-beta.0` on Hex and npm is tag `v0.55.0-beta.0`. `@version` in
`mix.exs` is authoritative. Publish both packages for every release, also when
only one side changed. Prereleases (a version with `-`) go to npm's `beta`
dist-tag, stable versions to `latest`.

Publishing is manual: no workflow builds or publishes the packages yet.

1. On a branch off `main`, set the version:
   `scripts/release-version bump X.Y.Z[-beta.N]`.
   It writes `mix.exs`, `assets/package.json` (version and
   `publishConfig.tag`) and any generator pin that names the old version
   exactly, then runs `scripts/release-version check`. That check is part
   of `mix check` and CI and fails when the versions disagree.
2. Collate the changelog: `scripts/changelog collate` moves the
   `changelog.d/` fragments into the `## … (Unreleased)` section of
   `CHANGELOG.md` and deletes them. Rename that heading to `## X.Y.Z[-beta.N]`
   and review the `### Upgrading` prose.
3. Run `mise exec -- mix check`, then commit as `Release X.Y.Z[-beta.N]`.
4. Open a pull request. Its CI runs the unit suite, documentation, the
   consumer asset build and the E2E suite; merge it once green
   (`scripts/queue <PR>`).
5. Check out the merged commit with a clean working tree, check the tag
   against the version with
   `scripts/release-version check --tag vX.Y.Z[-beta.N]`, then tag and push:
   `git tag vX.Y.Z[-beta.N]` and `git push origin vX.Y.Z[-beta.N]`.
   Pushing the tag runs the `Release tag` workflow, which checks it with
   `scripts/release-version check`; wait for it to pass. Steps 6 to 8 run from this checkout.
6. Review both packages:
   `cd assets && npm pack --dry-run` (source, CSS, `europa.json5`, the
   `vite/` helper and `LICENSE.md`; no tests or local files), and
   `mix hex.build`.
7. Publish npm first: `cd assets && npm publish`. The dist-tag comes from
   `publishConfig.tag`; check that `npm view @brandocms/brandojs dist-tags`
   shows the new version under `beta` (or `latest` for a stable release).
8. Publish Hex with its documentation:
   `MIX_ENV=docs mix docs --warnings-as-errors`, then
   `MIX_ENV=docs mix hex.publish` (`ex_doc` exists only in the `docs`
   environment). Hex marks a version with `-` as a prerelease.
9. Create the GitHub release from the tag, marked as a prerelease for a beta:
   `gh release create vX.Y.Z[-beta.N] --prerelease`, with the version's
   `CHANGELOG.md` section, the supported versions and the known limitations
   as notes.
10. In a pull request to `main`, add a new `## … (Unreleased)` heading at the top of
    `CHANGELOG.md` for the next fragments to collate into, and move `main`
    past the release so a Git install of it reads as newer:
    - After a prerelease, bump to the next one:
      `scripts/release-version bump X.Y.Z-beta.N+1`, committed as
      `Start X.Y.Z-beta.N+1`. Not back to `X.Y.Z-dev`: a `-dev` version
      counts as older than every prerelease of the same version, so
      upgrading from the published beta to it would be a downgrade.
    - After a stable release, bump to the next development version:
      `scripts/release-version bump X.Y+1.0-dev`, committed as
      `Start X.Y+1.0 development`.
