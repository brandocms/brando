- Brando parses HTML at runtime with `lazy_html` instead of Floki, and no longer brings in Floki.
  `lazy_html` is a precompiled NIF on lexbor, so a release ships it. It is an optional Brando
  dependency, as in Phoenix LiveView, so the application lists it for every environment:
  `mix brando.install`, `mix igniter.upgrade brando` and `scripts/prepare_055_deps.exs` drop the
  `only: :test` of the line a new Phoenix app has, or add `{:lazy_html, "~> 0.1.13"}`. By hand,
  do the same in `mix.exs` and run `mix deps.get`. Without it the application stops at boot with a
  message naming the line.
  An application that calls Floki itself (in `lib/`, or in its tests) lists it in its own deps:
  `{:floki, "~> 0.38"}`, or `{:floki, "~> 0.38", only: :test}` for tests only.
