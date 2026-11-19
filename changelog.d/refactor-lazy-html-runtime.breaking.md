- Brando parses HTML at runtime with `lazy_html` instead of Floki, and no longer brings in Floki.
  `lazy_html` is a precompiled NIF on lexbor, so a release ships it.
  In `mix.exs`, remove the `{:lazy_html, ">= 0.1.0", only: :test}` line a new Phoenix app has, or
  drop its `only: :test`: until then `mix deps.get` stops with "Dependencies have diverged".
  An application that calls Floki itself (in `lib/`, or in its tests) lists it in its own deps:
  `{:floki, "~> 0.38"}`, or `{:floki, "~> 0.38", only: :test}` for tests only.
