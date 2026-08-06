# Security Audit: Phase 7 (form-audit) — uncommitted working tree

Scope: `lib/brando/utils.ex`, `lib/brando/cdn/cdn.ex`,
`lib/brando/videos/uploaders/req_options.ex`, `mix.exs`, and the touched/new
tests. Pre-existing issues get one line.

## Executive Summary

No BLOCKER. The `overwrite:` short-circuit is **operator-config surface only** —
no request-, LiveView- or block-var-controlled path can set `:overwrite`, and the
key it produces cannot escape the configured upload path. One WARNING is real and
new-ish: the rewritten `ReqOptions` `@doc` enumerates the keys that reach past the
merge, and the enumeration is incomplete in exactly the direction that matters —
`:redirect_trusted` and `:connect_options` are missing, and Req's cross-host
credential stripping does **not** cover Bunny's `AccessKey` header, which the doc
implies is merely "alongside". The `mix.exs` `priv/` inclusion ships only
placeholders. Test fixtures are fake and env is restored.

---

## WARNING 1 — `ReqOptions` @doc omits the two config keys that leak the credential

- **Severity**: Medium (doc/threat-model completeness; actor is the config author)
- **Location**: `lib/brando/videos/uploaders/req_options.ex:29-50`
- **Issue**: the doc's "What still reaches past it" list names `:auth`, `:plug`,
  `:adapter`, `:params` and clears `:base_url`. Against req 0.7.2 the list is
  missing:
  - **`:redirect_trusted`** (`deps/req/lib/req/steps.ex:46, 1430-1432, 1509-1513,
    1571-1581`). By default Req deletes the `authorization` header and the `:auth`
    option on a redirect to a different host/scheme/port. `redirect_trusted: true`
    disables that: `remove_credentials_if_untrusted(request, true, _), do: request`
    (`steps.ex:1571`). A single configured boolean turns any 3xx from Mux or
    Cloudflare into credential delivery to the redirect target. This is strictly
    more dangerous than `:auth` (which only overwrites *our own* header) and the
    doc does not mention it.
  - **`:connect_options`** (`steps.ex:59`) — Finch/Mint transport options,
    including proxy configuration and TLS `transport_opts`. Reaches the same state
    as `:plug`/`:adapter` (route the authenticated request elsewhere, or turn off
    certificate verification) without replacing the adapter.
  - **`:finch`** — a custom Finch instance carries its own pool/proxy config; same
    class as `:connect_options`.
  - **`:into`** — hands the response body to a caller-supplied fun/pid; that body
    contains provider IDs and signed URLs.
  - Minor: `:retry`, `:max_redirects`, `:redirect_log_level` change
    availability/log volume only.
- **Verified correct in the doc**: `:auth` really does `put_header`, not
  `put_new_header` (`steps.ex:236, 240, 244`). `:base_url` really is inert for
  absolute URLs (`steps.ex:122-125` returns the request unchanged when
  `request.url.scheme != nil`).
- **Fix**: extend the list. Suggested wording for the two that matter:

  ```
  * `:redirect_trusted` — Req strips the `authorization` header and `:auth` on a
    cross-host redirect (`req/steps.ex:1571-1581`). `redirect_trusted: true`
    disables that stripping and sends the credential to any redirect target.
  * `:connect_options` / `:finch` — Mint/Finch transport config, including proxy
    and TLS verification. Same reach as `:plug`, by another route.
  ```
- **Scenario**: an operator copies `req_options: [redirect_trusted: true]` from an
  unrelated snippet (a common cargo-cult for provider CDNs that 302 across
  hostnames). Mux then 302s an `/uploads` call to a hostname it does not control
  (DNS takeover, or an attacker-influenced `Location`), and the Basic-auth token
  pair `access_token_id:access_token_secret` is sent to that host.
- **OWASP**: A05 Security Misconfiguration / A07 (credential exposure).

## WARNING 2 — Bunny's `AccessKey` is not covered by Req's redirect credential stripping (doc says less than this)

- **Severity**: Medium — and unlike WARNING 1 this needs **no configuration at
  all**
- **Location**: `lib/brando/videos/uploaders/bunny.ex:414` (`{"AccessKey", api_key}`)
  vs `deps/req/lib/req/steps.ex:1573-1581`
- **Issue**: `remove_credentials_if_untrusted/3` deletes exactly two things on a
  cross-host redirect: the `authorization` header and the `:auth` option. Bunny's
  credential is a custom `AccessKey` header set in `headers:`, so it is forwarded
  verbatim to whatever host the redirect points at, with Req's defaults, on every
  Bunny call. The `@doc` at `req_options.ex:37-39` mentions Bunny's header only to
  say that a configured `:auth` "lands alongside" it — it does not say that Req's
  own cross-host protection is blind to it.
- **Fix**: either add `redirect: false` to Bunny's built opts (built keys win the
  merge, so config cannot re-enable it), or note the gap in the doc:

  ```elixir
  # bunny.ex api_request/3
  [method: :get, url: url, headers: headers, redirect: false]
  ```

- **Scenario**: Bunny's API (or anything in front of it — a misrouted CNAME, an
  operator-set proxy) answers a `GET /library/4242/videos/…` with
  `302 Location: https://attacker.example/`. Req follows it, keeps
  `AccessKey: <bunny api key>`, and the Bunny library credential is disclosed.
  Mux and Cloudflare are safe here: both use `authorization`, which *is* stripped.
- **OWASP**: A10 SSRF (credential-forwarding variant).

## SUGGESTION 1 — `build_upload_key/2` `overwrite:` short-circuit is operator-only, but it makes a dormant option live

- **Severity**: Low
- **Location**: `lib/brando/utils.ex:1182-1193`
- **Reachability trace (this is the question asked, answered plainly)**: `file_cfg`
  is a Blueprint asset config — `Brando.Type.FileConfig` / `ImageConfig` /
  `VideoConfig`, each with `overwrite: false` by default
  (`file_config.ex:84`, `image_config.ex:50`, `video_config.ex:111`) and
  `:overwrite` validated as a boolean at compile time
  (`blueprint/asset_config_validator.ex:10, 37`). The only places a request-derived
  value mutates a resolved config are the folder overrides —
  `upload_manager.ex:390/718-725`, `image_list_live.ex:177/335-343`,
  `file_list_live.ex:176/330-338` — and all three write **`:upload_path` only**,
  through `FolderBrowser.absolute_folder/2`. `config_target` from the client
  selects among operator-defined configs; it cannot author one. **No client path
  sets `:overwrite`.** This is not an arbitrary-object-overwrite primitive; the
  actor is the operator who already owns `runtime.exs`.
- **Traversal check (also asked)**: clean. `get_valid_filename/2` →
  `slugify_filename/1` (`utils.ex:45-50`) → `split_filename/1` (`utils.ex:294-298`)
  uses `Path.basename/2`, which discards every directory component, and
  `Slug.slugify/1` drops `.`, `/`, and control/NUL bytes. The `random_filename`
  branch keeps only `Path.extname/1`. The `force_filename` branch
  (`utils.ex:1206-1209`) returns operator config verbatim. `concat_with_upload_path/2`
  then joins `media_url <> upload_path <> filename` and strips the leading slash,
  so with `overwrite: true` and a client-supplied `filename` the key stays inside
  the configured upload path.
- **Residual, and it is a genuine behaviour change**: for a field configured
  `overwrite: true` **without** `force_filename` or `random_filename`, the key is a
  pure function of the client's filename. Before this change the CDN path always
  consulted the bucket and uniquified on a hit, so overwrite was silently inert
  there; now any user with upload rights to that field can replace the bytes behind
  an existing object by uploading a file of the same name. The asset row and public
  URL are unchanged, so the swap is invisible in the CMS and survives CDN cache
  keys. That is the documented meaning of the option — flagging it so the
  behaviour change is a decision, not a side effect.
- **Fix (optional, doc-only)**: note in `Brando.Type.FileConfig`'s `:overwrite`
  docs (`file_config.ex:22`) that combining `overwrite: true` with a
  client-supplied filename means content replacement by any uploader, and that
  `force_filename` or `random_filename` is the intended pairing.

## SUGGESTION 2 — `get_s3_config/2` raise: message is clean, behaviour change is bounded

- **Severity**: Informational
- **Location**: `lib/brando/cdn/cdn.ex:114-134` (raise at `:124`)
- **Message**: names only config keys and module names (`:cdn`, `s3`,
  `Brando.Images`, `Brando.CDN`). **No values, no credentials, no bucket names.**
  Verified — same shape as the two pre-existing raises at `:76` and `:92`.
- **Callers** (`get_s3_config/2` in `lib/`): `cdn.ex:271`, `cdn.ex:427`
  (`head_object/2`), `cdn.ex:444` (`delete_object/2`), `uploads.ex:469`
  (`presign_put/3`) — all pass `as: :keyword_list`, which previously hit
  `Map.from_struct(nil)` and crashed anyway. So no in-repo caller loses a
  partially-working path; the change swaps an opaque `nil.__struct__/0` error for a
  message that names the missing config. Both call sites that can be reached from a
  live process already document that this raises and handle it
  (`uploads.ex:230`, `upload_manager.ex:493`).
- **Only caveat**: a downstream consumer calling with a non-`:keyword_list` `as:`
  previously got `nil` back and now gets a raise. That is the intended fail-closed
  direction (a `nil` S3 config downstream means unsigned/misdirected requests), but
  it is a library-visible behaviour change worth a CHANGELOG line if not already
  there.

## Verified clean

- **`mix.exs:100-108` `files:` / `priv/`** — inspected every path under `priv/`
  matching `*.cfg`, `*.py`, `.envrc*`, `*secret*`, `*key*`, `*.pem`. Results:
  `priv/templates/brando.install/{.envrc,.envrc.prod,.envrc.staging,deployment.cfg,fabfile.py}`
  plus migration files. All are EEx generator templates:
  - `.envrc.prod:2-3` and `.envrc:3` generate their secrets at render time with
    `:crypto.strong_rand_bytes(64)` — there is no static secret in the file.
  - `deployment.cfg:8, 13` carry the literal placeholders
    `prod_database_password` and `sudoer_pass`, plus `host.net` /
    `http://somesite.com`. Placeholders, not values.
  No `.pem`, key material, or real credential ships. The `files:` change did not
  newly add a secret-bearing path. (Separately: dropping `"assets"` removed
  `assets/node_modules/` from the tarball — a supply-chain surface reduction.)
- **Test fixtures** — `provider_client_test.exs:60, 131, 210, 233-234` and
  `req_options_test.exs:33-35, 75-79` use `"id"`, `"secret"`, `"bunny-key"`,
  `"api-token"`, `"account-id"`, `"hijacked"`, `"configured"`. Obvious fixtures; no
  real credential shape (no `mux_`/`sk_` prefixes, no base64 blobs).
- **Test env hygiene** — both files restore `Application` env correctly via
  `fetch_env` + `put_env`/`delete_env` in `on_exit`
  (`req_options_test.exs:19-29`, `provider_client_test.exs:31-46`), including the
  stored-`nil`-is-not-absent distinction. `req_options_test.exs:17` keys the app env
  on `__MODULE__`, so it cannot clobber a real provider's config even on failure.
  Both are `async: false`. Clean.
- Checked the rest of the diff for SQL interpolation, `String.to_atom`, `raw/1`,
  `binary_to_term`, and hardcoded secrets: none.

## Pre-existing (one line each, not introduced by Phase 7)

- `lib/brando/utils.ex:1202-1204` — `get_valid_filename("", _)` returns
  `{:error, :empty_filename}`, which then flows into `Path.join/2` and raises a
  `FunctionClauseError` instead of surfacing the error.
- `lib/brando/uploads.ex:397-398` — client-supplied `name` reaches
  `Path.join(["media", cfg.upload_path, filename])` for the presigned key, and is
  only slugified when `slugify_filename` is set; worth confirming
  `ensure_correct_extension/1` alone is enough there.
- `lib/brando_admin/live/upload_manager.ex:718-723` (and the two list LiveViews) —
  client-supplied `folder` becomes `cfg.upload_path`; the scoping lives entirely in
  `FolderBrowser.absolute_folder/2` and deserves its own targeted review.

## Tools to run manually (no Bash access here)

- `mix sobelow --exit medium`
- `mix deps.audit`
- `mix hex.audit`
- `mix hex.build` then inspect the tarball listing for `priv/` contents.
