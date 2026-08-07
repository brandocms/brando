# Security Review: Brando CMS — last 5 commits on `next`

Scope: `d3a47fbf5..` back 5 commits. Files reviewed in the diff: `lib/brando/cdn/cdn.ex`,
`lib/brando/utils.ex`, `lib/brando/videos/uploaders/bunny.ex`,
`lib/brando/videos/uploaders/req_options.ex`, `mix.exs`, tests.

## Executive Summary

The central fix (`40feac3db`) is **correct and complete**. Every claim in the commit's
inline rationale was independently verified against `deps/req/lib/req/steps.ex` and
holds. **No BLOCKER.** Two WARNINGs and two SUGGESTIONs follow, one of which
(credential-in-exception-message) is pre-existing but sits squarely in the code the
diff touches.

---

## Verification of the Bunny redirect fix

Files opened to verify: `deps/req/lib/req/steps.ex`, `deps/req/lib/req.ex`,
`lib/brando/videos/uploaders/bunny.ex`, `lib/brando/videos/uploaders/req_options.ex`,
`lib/brando/videos/uploaders/mux.ex`, `lib/brando/videos/uploaders/cloudflare.ex`,
`test/brando/videos/provider_client_test.exs`.

### 1. Is the described Req behaviour accurate? — **Yes**

`deps/req/lib/req/steps.ex:1571-1582`:

```elixir
defp remove_credentials_if_untrusted(request, true, _), do: request

defp remove_credentials_if_untrusted(request, _, location_url) do
  if {location_url.host, location_url.scheme, location_url.port} ==
       {request.url.host, request.url.scheme, request.url.port} do
    request
  else
    request
    |> Req.Request.delete_header("authorization")
    |> Req.Request.delete_option(:auth)
  end
end
```

Exactly two deletions, both named literally. A custom `AccessKey` header is not
touched. `strip_redirect_userinfo/1` (`steps.ex:1531-1540`) and
`change_post_to_get/2` (`steps.ex:1559-1565`) are the only other mutations in
`build_redirect_request/3`, and neither removes arbitrary headers. The described
pre-fix leak was real: a 302 from `video.bunnycdn.com` to an attacker host forwarded
the Bunny library API key verbatim on stock defaults.

### 2. Does `redirect: false` fully close it? — **Yes, no residual path**

`steps.ex:1464-1475`:

```elixir
def redirect({request, response}) do
  redirect? = ... Req.Request.get_option(request, :redirect, true)
  with true <- redirect? && response.status in [301, 302, 303, 307, 308],
```

`redirect?` is the first term of the `with`, so `false` short-circuits before
`build_redirect_request/3` is ever called. `build_redirect_request/3`
(`steps.ex:1501`) is the **only** caller of `remove_credentials_if_untrusted/3`, and
`Req.Steps.redirect/1` is the only redirect-following code in Req.

Residual paths checked and cleared:

- **`:into` / async streaming** — the `Req.Response.Async` cancel
  (`steps.ex:1481-1483`) is *inside* the now-dead branch; nothing else re-issues.
- **retry** — the retry step re-runs the same `request.url`; it does not read
  `location`.
- **`:location_trusted` / `:follow_redirects`** legacy aliases — both are read inside
  the same dead branch (`steps.ex:1466`, `:1507`), so neither reactivates it.
- Bunny's three calls are JSON REST against `@base_url` (`bunny.ex:41`); a 3xx now
  falls to the non-2xx clause (`bunny.ex:455-457`) and returns `{:error, body}`.

The regression test at `test/brando/videos/provider_client_test.exs:176-206` asserts
the strong form: `refute_received {:request, "evil.example.com", _}` — the redirect is
not followed *at all*, not merely followed without the header.

### 3. Applied to all three branches? — **Yes, 3 of 3**

`bunny.ex:440` (`:get`), `:443` (`:post`), `:446` (`:delete`). Counted directly.

### 4. Can config re-enable redirects? — **No. Not a blocker.**

`req_options.ex:83`:

```elixir
Keyword.merge(configured || [], built_opts)
```

`Keyword.merge/2` gives the **right** argument precedence, and `built_opts` is the
right argument. A `runtime.exs` `req_options: [redirect: true]` loses. Verified the
argument order at the call site too: `bunny.ex:449` passes `request_opts` (the built
list) as the second argument. The `|| []` correctly treats an explicitly-stored `nil`
as absent.

### 5. Mux and Cloudflare — **same class of bug is absent**

- **Mux** (`mux.ex:556-559`): `{"authorization", "Basic #{auth}"}` plus
  `content-type`. The credential is in `authorization`, which Req deletes itself. No
  other custom header, and `@base_url` (`mux.ex:39`) carries no query string.
- **Cloudflare** (`cloudflare.ex:277-279`): `{"authorization", "Bearer #{api_token}"}`
  plus `accept`. Its extra headers (`cloudflare.ex:129-133`) are `tus-resumable`,
  `upload-length` and `upload-metadata` — the last is base64 of the *filename* and
  max-duration (`cloudflare.ex:266`), not a credential.
- **Query-string credentials**: none. Cloudflare's only query param is the literal
  `direct_user=true` (`cloudflare.ex:135`); Mux's `build_playback_url/2`
  (`mux.ex:272-283`) appends only three allowlisted keys and is not an authenticated
  request.

Cloudflare's TUS `location` handling is separately well-guarded:
`valid_upload_url?/1` (`cloudflare.ex:311-319`) requires `https` and a
`.videodelivery.net` host with a mandatory leading dot, so there is no
suffix-confusion bypass (`evil-videodelivery.net` fails).

### 6. Same pattern elsewhere in `lib/` — **none found**

Grepped the whole tree for `Req.(request|get|post|put|delete|new)`, `HTTPoison`,
`Finch.`, `:hackney`, `Tesla`. Total outbound-HTTP call sites: four —
`bunny.ex:451`, `mux.ex:575`, `cloudflare.ex:287`, and `oembed.ex:18`
(unauthenticated; see below). No other module sends a custom credential header or a
credential in a URL. S3 goes through ExAws, which signs per-request rather than
carrying a bearer credential across a redirect.

---

## Findings

### WARNING — S3 credentials inspected into an exception message

- **Severity**: WARNING (pre-existing, but in the diff's blast radius)
- **Location**: `lib/brando/cdn/cdn.ex:292-299`; struct at `lib/brando/cdn/s3_config.ex:8-12`
- **Issue**:

  ```elixir
  s3_config = get_s3_config(config, as: :keyword_list)   # cdn.ex:289
  if !s3_bucket do
    raise """
    upload_image -- missing s3_bucket for config
    #{inspect(s3_config, pretty: true)}
    """
  end
  ```

  `get_s3_config/2` with `as: :keyword_list` is
  `%Brando.CDN.S3Config{} |> Map.from_struct() |> Map.to_list()`
  (`cdn.ex:95-101`, `:104-112`, `:145-151`). `Brando.CDN.S3Config` is a plain
  `defstruct` with `access_key_id` and `secret_access_key` (`s3_config.ex:8-9`) and
  **no `@derive Inspect` redaction**. So the raise embeds the live access key and
  secret in plaintext in the exception message.

  This is not a dead path: `upload_image/4` runs inside
  `Brando.Worker.ImageUploader`, so the message reaches the Logger, the persisted
  Oban job `errors` column, and Sentry (`mix.exs:134`) — three places with much
  broader read access than `runtime.exs`. It fires precisely when the CDN config is
  half-populated (bucket missing, credentials present), which is the realistic
  misconfiguration.

  The prose added in this diff (`cdn.ex:117-140`, `:425-440`) walks through
  `Map.from_struct` on a possibly-`nil` S3 config and a `BadMapError` at `:429` in
  careful detail, and adds a guard for the nil case — but does not address the case
  where the struct *is* populated and gets inspected.

- **Fix**:

  ```elixir
  # lib/brando/cdn/s3_config.ex
  @derive {Inspect, except: [:access_key_id, :secret_access_key]}
  defstruct access_key_id: nil, ...
  ```

  and drop the interpolation from the raise, or narrow it to the non-secret keys
  (`Keyword.take(s3_config, [:host, :region, :scheme])`).
- **OWASP**: A09:2021 Security Logging and Monitoring Failures / CWE-532.

### WARNING — Mux and Cloudflare still rely on Req's stripping, and `:redirect_trusted` can switch it off

- **Severity**: WARNING (low likelihood; config-author actor)
- **Location**: `lib/brando/videos/uploaders/mux.ex:561-571`,
  `lib/brando/videos/uploaders/cloudflare.ex:281-285`
- **Issue**: Bunny is now immune to cross-host credential forwarding by construction
  (`redirect: false`, which config cannot override). Mux and Cloudflare are immune
  only *conditionally* — they depend on `remove_credentials_if_untrusted/3` running,
  and `req_options.ex:40-42` correctly documents that a configured
  `req_options: [redirect_trusted: true]` makes it a no-op (`steps.ex:1571`). Neither
  provider names `:redirect_trusted` in its built options, so the config wins there.
  Result: `redirect_trusted: true` set for any reason (a proxy workaround, a copied
  snippet) silently re-arms Basic/Bearer forwarding for two of three providers, with
  nothing at those call sites saying so.

  This is a *residual*, not a regression — the fix did not make it worse. But the
  asymmetry is now invisible: a reader of `mux.ex` sees no redirect handling at all.
- **Fix**: add `redirect: false` to the Mux and Cloudflare built option lists too.
  Neither follows redirects today (both are JSON REST against fixed API hosts;
  Cloudflare's TUS provisioning reads `location` from a 2xx, not a 3xx), so this is
  behaviour-preserving and makes all three providers uniform and config-proof.
  Alternatively add `redirect_trusted: false` to all three, which closes the seam
  directly while leaving redirect-following intact.

### SUGGESTION — `Brando.OEmbed` follows redirects to arbitrary hosts

- **Severity**: SUGGESTION (pre-existing, unauthenticated)
- **Location**: `lib/brando/oembed.ex:13-22`
- **Issue**: `Req.get!(url)` with Req's default `redirect: true`. The *initial* host is
  allowlisted (`oembed.ex:3-6`, YouTube/Vimeo only) and the user-supplied portion is
  URI-encoded into a query param at `:14`, so this is not an open SSRF. But either
  provider redirecting — or an open redirect on either provider — sends a server-side
  request to an arbitrary host. No credentials are attached, so impact is limited to
  SSRF-style internal reachability.
- **Fix**: `Req.get!(url, redirect: false)`, or `max_redirects: 2` plus a host check on
  the final URL.

### SUGGESTION — `mix.exs` package `files:` change

- **Location**: `mix.exs:100-108`
- **Verified**: dropping `config`, `test` and `assets` removes shipped surface and
  loses nothing a consumer needs. `priv/` (generator templates, migrations) and `lib/`
  still ship. The rationale at `mix.exs:80-99` is accurate: dependencies compile in
  `:prod`, so `elixirc_paths(:test)` (`mix.exs:54`) never fires for a dep and
  `test/support` was never compiled by consumers anyway. The `assets/node_modules`
  point is a real 120 MB tarball-size and supply-chain-surface win.
- **Nothing secret was previously shipped**: the removed `config/` and `test/` trees
  contain only fixtures. The scaffolding placeholders that remain in `priv/`
  (`deployment.cfg`, `.envrc.prod`) are template placeholders, correctly called out at
  `mix.exs:87-90`.
- **Not a regression, but worth confirming**: `.formatter.exs` is absent from the
  `files:` list and appears to have been absent before this change too — so this diff
  did not break it. It does matter, though: `.formatter.exs:173` defines an `export:
  [locals_without_parens: ...]` block covering Brando's and Spark's DSL, and Mix reads
  that from the dep's *tarball* for `import_deps: [:brando]`. If consumers currently
  rely on that, it has never worked from Hex. Adding `".formatter.exs"` to `files:` is
  cheap and carries no security cost. Non-security; flagged only because this is the
  one candidate for "needed and now missing".

### Test fixtures — clean

`test/brando/videos/provider_client_test.exs`, `upload_test.exs`,
`uploaders/cloudflare_test.exs`, `uploaders/mux_test.exs`: every credential is an
obvious fixture (`"bunny-key"`, `"api-token"`, `"id"`/`"secret"`, `"TESTKEY"`,
`"TESTSECRET"`, `"webhook-secret"`). No real-looking tokens — no `sk_`/`pk_`/`AKIA`
prefixes, no JWTs, no high-entropy strings.

---

## Pre-existing issues (one line each)

- `lib/brando/utils.ex:905-907` — `binary_to_term/1` calls `:erlang.binary_to_term/1`
  without `[:safe]`; atom-exhaustion / struct-forgery if ever fed an untrusted binary.
- `lib/brando/cdn/cdn.ex:498` — `"attachment; filename=\"#{filename}\""` does not
  escape `"` in the filename; header-value splitting is bounded by upstream
  slugification, but the escape belongs here.
- `lib/brando/cdn/cdn.ex:364` — `Logger.error(inspect(e))` on an `ExAws.Error`; low
  risk (ExAws errors do not carry the config), noted for completeness.
- `lib/brando/utils.ex:890` — `String.to_atom/1` in `generate_secure_cookie/0`;
  bounded (64 random chars, generation-time only), not a DoS vector.

Checked and clean across the diff: SQL injection (both new `fragment/2` uses,
`cdn.ex:169` and `:213`, pin with `^`), XSS/`raw/1`, CSRF, `String.to_atom` on user
input, and path traversal in `build_upload_key/2` (`utils.ex:1174-1193` — filenames
are slugified or randomised before joining, and `force_filename`/`overwrite` are
blueprint config, never client input; validated at
`asset_config_validator.ex:190-197`). The `overwrite: true` short-circuit added at
`utils.ex:1189` skips the bucket-collision check by design; since `overwrite` is
developer config and the filename is still sanitised, this is not a
client-controllable overwrite primitive.

---

## Recommendations (priority order)

1. Redact `Brando.CDN.S3Config` with `@derive {Inspect, except: [...]}` and remove the
   `inspect(s3_config, ...)` from the raise at `cdn.ex:292-299`.
2. Add `redirect: false` (or `redirect_trusted: false`) to Mux and Cloudflare so all
   three providers are config-proof, not two of three.
3. Pin `oembed.ex:18` to `redirect: false`.
4. Add `[:safe]` to `Brando.Utils.binary_to_term/1`, or audit its callers.
5. Consider adding `".formatter.exs"` to the package `files:` list (non-security).

## Tools to run manually (this agent has no Bash access)

- `mix sobelow --exit medium`
- `mix deps.audit`
- `mix hex.audit`
