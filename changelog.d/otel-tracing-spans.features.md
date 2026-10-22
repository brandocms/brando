- Brando records `brando.*` OpenTelemetry spans for rendering, queries, the admin form, live
  preview, media, CDN calls, search and builds, and `mix brando.gen.otel` sets up the SDK and
  instrumentation ([#3128](https://github.com/brandocms/brando/pull/3128)).

- `Brando.Tracing.LiveView.setup/0` adds spans for LiveComponent updates and renders, and `@decorate
  span(...)` from `Brando.Tracing.Decorator` traces an application's functions
  ([#3128](https://github.com/brandocms/brando/pull/3128)).
