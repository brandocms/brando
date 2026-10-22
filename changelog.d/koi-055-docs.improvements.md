- The 0.53 upgrade guide covers what a real site upgrade ran into, with a checklist for sites
  upgraded with an earlier Brando revision ([#3168](https://github.com/brandocms/brando/pull/3168)).

- The guides say to keep `:brando` out of `reloadable_apps`, which slows every development request
  ([#3168](https://github.com/brandocms/brando/pull/3168)).
  Remove `:brando` from the endpoint's `reloadable_apps`; after editing a local Brando checkout, run
  `mix deps.compile brando` and restart.
