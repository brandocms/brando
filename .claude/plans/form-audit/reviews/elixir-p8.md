# Code Review: Phase 8 (HEAD~5..HEAD, `next`)

## Summary
- **Status**: ⚠️ Changes Requested
- **Issues Found**: 5 (1 BLOCKER, 2 WARNING, 2 SUGGESTION)

Scope: `lib/brando/cdn/cdn.ex`, `lib/brando/utils.ex`,
`lib/brando/videos/uploaders/{bunny,req_options}.ex`, `mix.exs`, and the five
touched test files. Every vendored-code claim below was checked by opening
`deps/req/lib/req/steps.ex`, `deps/phoenix_live_view/lib/phoenix_live_view/test/client_proxy.ex`,
`lib/brando/cdn/config.ex`, `lib/brando/cdn/s3_config.ex` and `lib/brando/upload.ex`.

---

## Verified correct — no action

**`req_options.ex` `@doc`, against `deps/req/lib/req/steps.ex` (req 0.7.2):**

| Claim | Result |
|---|---|
| `:auth` writes with `put_header/3`, not `put_new_header/3` (`:236, 240, 244`) | exact — all three `auth/2` clauses call `Req.Request.put_header(request, "authorization", …)` |
| `encode_body/1` tests `:form` (`:486`) and `:form_multipart` (`:490`) **before** `:json` (`:497`) | exact — one `cond`, that order |
| `remove_credentials_if_untrusted(request, true, _), do: request` (`:1571`) | exact; the other clause (`:1573-1582`) deletes only the `authorization` header and the `:auth` option |
| `:base_url` inert on absolute URLs — `put_base_url/1` (`:123`) | exact: `if request.url.scheme != nil, do: request` |
| `@spec merge(module(), keyword()) :: keyword()` | matches the body (`get_env/3` with `[]` default → `Keyword.get/2` → `Keyword.merge/2`); `nil` config is absorbed by `|| []`, so `keyword()` out is right |

**`live_case.ex:95-126`, against vendored `phoenix_live_view 1.2.8`:** all five
citations correct. `put_view/3` `:846` (monitors at `:849`, writes `pids:` at
`:857`), `handle_info({:DOWN, …}, state)` `:542` → `{:stop, reason, state}`
`:545`, `fetch_view_by_pid/2` `:909` reading `state.pids`, and
`recursive_detect_added_or_removed_children/4` `:983` calling `put_view/3` at
`:1001`. The Phase 7 blocker is closed, and the "no root/child distinction"
conclusion follows from the code as written.

**SEC-1 (`bunny.ex`):** `redirect: false` is on **all three** branches — `:440`
GET, `:443` POST, `:446` DELETE. Nothing in the module needs a redirect: all
three are JSON REST calls against the fixed `@base_url`, and a 3xx now falls into
the `status not in 200..299` clause (`:455-457`) as `{:error, body}`. The
precedence argument holds: `merge/2` is `Keyword.merge(configured || [], built_opts)`
(`req_options.ex:83`) and `Keyword.merge/2`'s right side wins, so `runtime.exs`
cannot re-enable it.

**Tests:** `provider_client_test.exs:176-206` asserts the real defect (stub 302 →
`assert_received {:request, "video.bunnycdn.com", ["bunny-key"]}` +
`refute_received {:request, "evil.example.com", _}`) and captures the log so the
tracked stdout baseline stays stable — that is the right shape.
`req_options_test.exs:124-145` pins the `:auth`-reaches-the-wire claim in the
stub rather than in the keyword list, which is the only place it is falsifiable.
`form_recovery_test.exs:109-137` now carries the three premises and asserts
`{:proxy_stopped, :killed}`; the `:killed` reason is what `client_proxy.ex:545`
propagates, so the assertion is causal as claimed. `utils.ex:1185`'s citation of
`upload.ex:321-327` is exact.

---

## Blockers

### 1. `lib/brando/cdn/cdn.ex:434` — the W-1 replacement citation is itself wrong

> "The raise arrives one line later at `cdn_config.bucket` (`:429`)"

`bucket = cdn_config.bucket` is at **`cdn.ex:456`**, inside `head_object/2`
(`:453`). Verified by grepping `cdn_config\.bucket` across `lib/`: only `:456`,
`:473` (`delete_object/2`) and `uploads.ex:474` match. Line `:429` is *inside the
`@doc` block being written* — the words "a timeout, a signature failure — reads
as **occupied**". It is also three lines after `get_s3_config/2` (`:454`), not
one.

This is the precise defect class Phase 8A exists to eliminate, reintroduced
within the same phase in a different file. Per 8A's own rule the repair is a
function head:

```elixir
# Current
  raise arrives one line later at `cdn_config.bucket` (`:429`), where

# Suggested
  raise arrives in `head_object/2`, at its `cdn_config.bucket`, where
```

## Warnings

### 2. `lib/brando/cdn/cdn.ex:435` — `BadMapError` is the wrong exception

`head_object/2:455` does `cdn_config = Map.get(field_cfg, :cdn)`, which is `nil`
when `field_cfg` carries no `:cdn`. `nil` is an atom, and `atom.field` is
compiled as a remote call, so `cdn_config.bucket` raises

    ** (UndefinedFunctionError) function nil.bucket/0 is undefined or private

not `BadMapError`. `BadMapError` is what a *non-atom* non-map produces — which is
exactly why the sibling claim at `cdn.ex:131` (`Map.get/3` on a keyword list at
`:72`) **is** correct; the two cases are not the same error and the doc uses one
name for both.

The paragraph is headed "Measured rather than read", so there are two readings
and both contradict the sentence: either the exception name is wrong, or the
measurement passed a keyword-list `field_cfg`, in which case the raise is a
`BadMapError` from `Map.get/2` at `:455` — a different line and a different
expression from the one cited. Confirm with `iex -e 'x = nil; x.bucket'` before
editing. The surrounding conclusion ("raises before any network call, so callers
on a possibly-CDN-less config must check first") is unaffected and correct: the
`%Brando.CDN.Config{}` default `s3: %Brando.CDN.S3Config{}` (`config.ex:9`) does
make `get_s3_config/2`'s fallback succeed with all-`nil` credentials
(`s3_config.ex:8-9`), so the failure genuinely is the bucket, not the S3 config.

### 3. `lib/brando/videos/uploaders/req_options.ex:52` — citation staled by this diff's own change

> "`:json` — Bunny's GET and DELETE build no body (`bunny.ex:422, 428`)"

SEC-1 inserted an 18-line comment at `bunny.ex:419-436`, so `:422` and `:428` are
now that comment's text ("things: the `authorization` header and the `:auth`
option", "…defaults with no config involved. Mux and Cloudflare…"). The GET and
DELETE branches moved to `bunny.ex:440` and `:446`.

Two tasks in one phase again wrote about each other's code — the same collision
W-1 was raised for. Same repair as #1: name `api_request/3`'s `case method do`
branches instead of lines. Worth a rule for Phase 9: a cross-file line citation
must be re-checked by whichever task last edited the cited file.

## Suggestions

### 4. `lib/brando/cdn/cdn.ex:124-127` — unstated subject contradicts `:117`

"Reaching this at all needs `:cdn` present *and* carrying an explicit `s3: nil`"
sits four lines under "The field config carries no `:cdn`, so this is the
fallback". Read together they describe one config object and disagree. The
`:cdn` that must carry `s3: nil` is **`Brando.Images`'** — `s3_config` comes from
`config(Brando.Images, :s3)` (`:115` → `config/1` `:64-66`) — not `field_cfg`'s.
A `field_cfg` with `cdn: %{enabled: true, s3: nil}` matches the clause at `:104`
and never reaches this one.

Slightly narrow too: *any* `Brando.Images` `:cdn` value whose `:s3` resolves to
`nil` reaches the raise (an explicit `s3: nil`, or a plain map with no `:s3`
key). The populated default only applies when `:cdn` is entirely unset, because
`config/1` substitutes `%Brando.CDN.Config{}` only on a falsy lookup.

Name the subject: "…needs `Brando.Images`' own `:cdn` config to be present *and*
to resolve `:s3` to `nil`".

### 5. `mix.exs:163` — the req doc's line numbers have no drift signal

`{:req, "~> 0.5 or ~> 1.0"}` spans versions in which `steps.ex`'s line numbers
will not hold, while `req_options.ex` cites eight of them. The behavioural drift
that matters is covered — `req_options_test.exs:124` reddens if `:auth` ever
switches to `put_new_header/3`. The line numbers are not, and unlike
`phoenix_live_view` there is no version assertion naming what they were read
against. Cheapest fix is the one 8A already chose elsewhere: cite `auth/2`,
`encode_body/1`, `put_base_url/1` and `remove_credentials_if_untrusted/3` by
name, and keep "against req 0.7.2" as the single version statement.

## Packaging (`mix.exs`) — no regression

`links: %{"GitHub" => …}` (`:78`) satisfies Hex's required metadata. The `files`
list (`:100-108`) keeps `lib`, `guides`, `priv`, `mix.exs`, `README.md`,
`CHANGELOG.md`, `UPGRADE.md`; nothing compiled from `lib/` or templated from
`priv/templates/` resolves into `assets/` at build time, and `elixirc_paths(:test)`
is unreachable for a dependency, so dropping `test` is safe as the comment states.
