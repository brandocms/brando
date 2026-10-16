- **The legacy `a.primary`, `a.secondary`, `.tertiary` and `.danger` button
  styles are gone; use `.btn`.** An application's admin screens that still
  write them change `primary` to `btn btn--primary`, `secondary` to `btn`,
  `tertiary` to `btn btn--quiet btn--sm`, `danger` to `btn btn--danger` and
  `primary danger` to `btn btn--primary btn--danger`; `small` becomes
  `btn--sm`, and `fullWidth`, `narrow` and `fw` have no replacement. A plain
  `<.link class="primary">` in the page header keeps its look.
