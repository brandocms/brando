- `mix igniter.upgrade brando` moves a `-dev` installation onto a prerelease of the same version,
  such as `0.55.0-dev` to `0.55.0-beta.0` ([#3193](https://github.com/brandocms/brando/pull/3193)).

- `mix igniter.upgrade brando` runs Brando's version hook instead of stopping with "Versioned
  upgrades require FROM TO arguments" ([#3193](https://github.com/brandocms/brando/pull/3193)).
