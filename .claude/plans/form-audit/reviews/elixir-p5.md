# Elixir Review: form-audit Phase 5

## Summary
- **Status**: ✅ Approved
- **Issues Found**: 3 (0 blocker, 1 warning, 2 suggestions)

## Verification of claimed behavior

1. **ExAws 404 translation (`lib/brando/cdn/client.ex:96`)** — CORRECT.
   `deps/ex_aws/lib/ex_aws/request.ex` builds all non-2xx responses as
   `{:error, {:http_error, status, body}}` (lines 66, 160, 165, 204), so
   `{:error, {:http_error, 404, _}} -> {:error, :not_found}` matches the real
   shape ExAws returns. The moduledoc's documented "known limit" (403 masking
   404 without `s3:ListBucket`) is accurate — no other head_object error shape
   exists in the ExAws source that would need translating.

2. **`Keyword.merge` reversal in the three uploaders** — CORRECT in all three
   (`bunny.ex:437`, `cloudflare.ex:283-287`, `mux.ex:579`). `Keyword.merge/2`
   has right-argument-wins semantics, so `Keyword.merge(req_options(), request_opts)`
   makes the built `request_opts` (method/url/headers/json) win over any
   `:req_options` config entry with the same key — matches the stated intent
   that config cannot silently unset the built auth header. Consistent shape
   across Bunny, Cloudflare, and Mux.

3. **`error_translator.ex`** — `Forms.list_fields/1` exists (`forms.ex:496`)
   and matches the new call site's arity/usage. No dangling reference.

4. **`mix.exs` package `files:`** — dropping `config`/`test` is safe. `priv/`
   (migrations, seeds) and `guides/` (referenced by `docs.extras`) are still
   listed. No `lib/` module references a path under `config/` or `test/` at
   runtime; `elixirc_paths(:test)` only fires when compiling brando itself,
   not as a dependency.

## Warnings

1. **`lib/brando/videos/uploaders/cloudflare.ex:283-287` — duplicated merge-order comment/logic, no shared helper.**
   The exact same `Keyword.merge(req_options, built_opts)` pattern plus its
   comment is copy-pasted across `bunny.ex:437`, `cloudflare.ex:283-287`, and
   `mux.ex:579` (each provider also duplicates `req_options/0`/`get_config/2`
   and the whole `api_request/3` skeleton). Not new to this diff, but the
   Phase 5 change touched all three copies identically — a shared private
   helper (e.g. in a common uploader-support module) would prevent one of the
   three drifting out of sync with the other two on the next change, which is
   exactly the bug class this diff just fixed.

## Suggestions

1. **`lib/brando/cdn/client.ex:96`** — the `case` only has two branches
   (match + passthrough); `with` isn't warranted here, but consider
   documenting inline (one line) that `other` also covers `{:ok, _}` so a
   future reader doesn't have to check the callback spec to confirm success
   still flows through untouched. Minor, doc-only.

2. **`priv/repo/migrations/20260806000001_unique_block_uid_in_test_schema.exs`**
   — the moduledoc is excellent (explains the deliberate non-`null: false`,
   the symlink-into-e2e consequence, and the recovery command), but it's
   unusually long for a migration file relative to the one-line `change/0`.
   No action needed; flagging only because it's a lot of prose to keep in
   sync if the constraint strategy changes later.

## Pre-existing issues outside the diff
- `lib/brando/cdn/cdn.ex:311,354,362` — `s3_upload/7`/`ensure_bucket_exists/1` call `ExAws.request` directly, bypassing the `Brando.CDN.Client` seam (acknowledged/deliberate per config/test.exs comment, not a defect introduced here).
