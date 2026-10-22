- The admin has one badge, `.badge`, with the tones `badge--success`, `badge--attention`,
  `badge--error`, `badge--ai`, `badge--outline` and `badge--count`
  ([#3200](https://github.com/brandocms/brando/pull/3200)).
  The `large` badge modifier is removed. A listing that relied on the old mono uppercase look writes
  `badge uppercase`.

- A shared admin button, `.btn`, in three sizes (`btn--sm`, default, `btn--lg`), with
  `btn--primary`, `btn--save`, `btn--quiet`, `btn--danger`, `btn--ai`, `btn--icon` and `btn-group`;
  its corners and heights come from `theme.radius` and `theme.controls` in `europa.json5`
  ([#3200](https://github.com/brandocms/brando/pull/3200)).

- The unused button styles `.btn-primary`, `.btn-secondary`, `.btn-outline-primary`,
  `.btn-outline-secondary`, `.btn-small`, `.btn-stealth` and `.button-group-horizontal` are removed
  ([#3200](https://github.com/brandocms/brando/pull/3200)).
  An application's admin screens that used one of them use `.btn`.

- Every admin colour has an entry in `theme.colors`, so an application can change any of them in its
  own `europa.json5` ([#3200](https://github.com/brandocms/brando/pull/3200)).
