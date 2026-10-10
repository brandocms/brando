- **Brando's own work shows up in OpenTelemetry traces** (#3128). Block
  rendering and Liquid, create/update/delete and list queries, revisions,
  cache eviction and warm-up, the admin form's load and save phases, live
  preview, image processing, uploads, CDN calls, search, the sitemap and
  static builds record `brando.*` spans. Brando depends on
  `opentelemetry_api` only, so without the SDK a span costs a function call;
  `mix brando.gen.otel` sets up the SDK, an exporter and the Phoenix,
  LiveView, Ecto and Oban instrumentation. `Brando.Tracing.LiveView.setup/0`
  adds spans for LiveComponent `update/2` and rendering, which Phoenix's
  instrumentation leaves out. Exceptions are recorded by type and stack
  trace, without their message. `@decorate span(...)` from
  `Brando.Tracing.Decorator` traces a function clause in an application too.
  `mix brando.gen.otel` now sets up OpentelemetryOban with `plugin:
  :disabled` instead of the deprecated `trace:` option.
