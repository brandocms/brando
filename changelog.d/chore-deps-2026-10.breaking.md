- Brando requires Sentry 14 (`{:sentry, "~> 14.0"}`)
  ([#3241](https://github.com/brandocms/brando/pull/3241)).
  In `config :sentry`, replace `enable_logs: true` with `logs: [level: :info]`. `:enable_metrics` is
  removed: metrics are sent unless a `:before_send_metric` callback drops them.
  See Sentry's [13.x to 14.x upgrade guide](https://hexdocs.pm/sentry/upgrade-14.x.html).
