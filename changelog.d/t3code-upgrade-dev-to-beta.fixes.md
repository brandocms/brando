- **`mix igniter.upgrade brando` moves a `-dev` installation onto a
  prerelease of the same version.** Semantic versioning orders prerelease
  identifiers alphabetically, so `0.55.0-dev` counted as newer than
  `0.55.0-beta.0` and the hook stopped the upgrade as a downgrade. A `-dev`
  version now counts as older than every other prerelease and the release of
  the same version, in the downgrade guard, the check against the loaded
  dependency and the oldest supported source (so `0.54.0-beta.0` is accepted
  as a source too). Moving from `0.55.0-dev` to `0.55.0-beta.0` runs no
  version recipe and plans missing framework migrations as before; a real
  downgrade such as `0.55.0-beta.0` to `0.55.0-dev` is rejected.

- **`mix igniter.upgrade brando` runs the version hook.** Igniter passes the
  old and new versions as `Version` structs, and the hook only accepted
  strings, so every upgrade stopped with "Versioned upgrades require FROM TO
  arguments". It now accepts both.
