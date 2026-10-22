- Brando's copied upgrade migrations (`brando_61`, `_89`, `_103`, `_108`, `_125` and `_144`) compile
  without warnings ([#3167](https://github.com/brandocms/brando/pull/3167)).
  If `mix brando.migrations.check` reports a not-yet-run copy as differing from its template, copy
  it again with `mix brando.gen.migrations`.
