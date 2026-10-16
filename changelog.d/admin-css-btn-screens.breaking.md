- **`.add-entry-button` and `.module-add-button` no longer style a button;
  add `btn`.** An application's admin screens that write either class on
  its own get an unstyled button: write `class="btn add-entry-button"`, and
  `class="btn"` for `module-add-button`, whose rule is gone.
  `.add-entry-button` keeps only its top margin.
