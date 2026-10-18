- **Brando requires Sentry 14** (`{:sentry, "~> 14.0"}`, from 13.5). Sentry
  14 removes the `:enable_logs` and `:enable_metrics` options: an
  application whose `config :sentry` sets `enable_logs: true` sets
  `logs: [level: :info]` instead, or it reports crashes but no structured
  logs, and metrics are always sent unless a `:before_send_metric` callback
  drops them. Sentry 14 also scrubs more by default (`[Filtered]` values,
  referer URLs, conn path parameters). See Sentry's
  [13.x to 14.x upgrade guide](https://hexdocs.pm/sentry/upgrade-14.x.html).
