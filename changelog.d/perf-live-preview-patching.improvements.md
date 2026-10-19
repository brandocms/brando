- The live preview does less work per edit and skips a render identical to the one it shows
  ([#3225](https://github.com/brandocms/brando/pull/3225)).

- Editing a block inside a slot patches only that block into the live preview
  ([#3225](https://github.com/brandocms/brando/pull/3225)).

- Ecto tracing from `mix brando.gen.otel` passes on only queries inside a recording span, which
  saves about 1 ms per live preview render ([#3225](https://github.com/brandocms/brando/pull/3225)).
  An application generated before deletes `lib/<app>/o11y/open_telemetry_ecto.ex` and runs `mix
  brando.gen.otel` again.
