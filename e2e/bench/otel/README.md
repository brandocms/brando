# Tracing the e2e project

Records OpenTelemetry traces from a running e2e server: Phoenix requests,
LiveView callbacks, Ecto queries, Oban jobs, and Brando's own spans
(`brando.*`). The app and the trace store can run on different machines, so the
store does not compete with the app for CPU.

## 1. Start the trace store

On the machine that keeps the traces:

```sh
e2e/bench/otel/stack up
```

This starts an OpenTelemetry Collector on `:4317` (gRPC) and `:4318` (HTTP) and
Jaeger's UI on `:16686`. The collector writes every span to
`~/.local/share/brando-otel/traces.jsonl` and forwards it to Jaeger. Jaeger
keeps spans in memory; the JSONL file survives `stack down`. `stack clear`
deletes it.

From another machine, the OTLP port must be reachable through the firewall,
for example on Fedora over Tailscale:

```sh
sudo firewall-cmd --zone=tailscale --add-port=4318/tcp --add-port=16686/tcp
```

## 2. Run the e2e server with tracing

The e2e project records and exports spans only when
`OTEL_EXPORTER_OTLP_ENDPOINT` is set; without it every span is non-recording.

```sh
cd e2e && source .envrc && mix deps.get
BRANDO_SEEDING=true MIX_ENV=e2e mix run priv/repo/e2e_seeds_large.exs   # once
OTEL_EXPORTER_OTLP_ENDPOINT=http://<trace-host>:4318 MIX_ENV=e2e mix phx.server
```

The server prints `E2E server ready on :<port>` (`.envrc` derives the port
from the checkout path). Log in with `admin@brandocms.com` / `brandocms` and
open the bench entries (`/bench-flat-5`, `-40`, `-115`, `/bench-nested`), or
drive them with the block-editor bench (see `../README.md`).

The first requests after a boot load modules and fill caches: one mount
took 611 ms in `BlockField.update` cold and 20 ms warm. Repeat an action, or
filter with `--since`, before reading timings.

Ecto spans carry the SQL text here (`db_statement: :enabled` in
`E2eProject.Application`); statements are parameterised, so no values.

## 3. Read the traces

- Jaeger: `http://<trace-host>:16686`, service `e2e_project`.
- Summaries of the JSONL file (`--help`-style usage at the top of the script):

  ```sh
  elixir e2e/bench/otel/summary.exs --since 10            # self time per span name
  elixir e2e/bench/otel/summary.exs --since 10 --slow 3   # slowest traces as trees
  elixir e2e/bench/otel/summary.exs --root save_form --repeats   # repeated SQL
  ```

  To read one step or spec at a time, record time windows and pass them
  with `--windows` (add `--exclude /e2e/,/sandbox,/__e2e` to drop the test
  harness's own requests):

  ```sh
  e2e/bench/otel/run-specs tests/pages/revisions.spec.js tests/search.spec.js
  elixir e2e/bench/otel/summary.exs --windows ~/.local/share/brando-otel/windows.tsv

  # editor flows on the large fixtures; prints FLOW <label> <start> <end> <wall ms>
  cd e2e/playwright && npx playwright test --config bench/playwright.bench.config.js traced-flows
  ```

  Run the regular specs against normally seeded data: the large fixtures
  change what several specs see (module suggestions, stale-block warnings).

  Don't move or delete `traces.jsonl` while the collector runs: it keeps
  writing to the open file. Use `stack clear` to start over.
