# Security Audit: Brando — Phase 6 (`git diff HEAD~5`)

## Executive summary

No BLOCKERs. Both changes with real security weight are sound:

1. **The overwrite guard is genuinely fail-closed.** `key_available?/2` returns
   `true` for exactly one return shape of `head_object/2`, and I traced every
   shape that function can produce. There is no path that yields "available" on
   an uninterpretable result.
2. **`ReqOptions.merge/2`'s argument order is correct at all three call sites**,
   and no credential reaches a log or an error tuple.

One WARNING: the `ReqOptions` docstring states a guarantee wider than the
mechanism delivers. `Keyword.merge/2` only defends keys the built options
*name*. Req has other option keys that write the same `authorization` header —
`:auth` chief among them — and those pass through untouched. The threat actor
there is whoever writes application config (already trusted), so this is a
defence-in-depth / accuracy issue, not an exploit.

The `mix.exs` hunk in this diff is **comment-only**. The `files:` list is
unchanged context. Nothing new lands in the hex package.

---

## 1. Overwrite guard — `lib/brando/cdn/cdn.ex:397`

**Verdict: sound. The fail-closed claim holds.**

```elixir
def key_available?(object_key, field_cfg) do
  head_object(object_key, field_cfg) == {:error, :not_found}
end
```

Strict `==` against a single literal, not `match?`. Enumerating everything
`Brando.CDN.head_object/2` (`cdn.ex:408`) can produce, via
`Brando.CDN.Client.impl().head_object/3`:

| Return / outcome | Origin | `key_available?` | Caller effect |
|---|---|---|---|
| `{:error, :not_found}` | `ExAws` impl translates **404 only** (`client.ex:96`) | `true` | key used as-is — correct, key is absent |
| `{:ok, %{status_code: 200, ...}}` | hit | `false` | suffixed |
| `{:error, {:http_error, 403, _}}` | bucket masking 404 without `s3:ListBucket` | `false` | suffixed — **this is the fix** |
| `{:error, {:http_error, 5xx, _}}` | provider fault | `false` | suffixed |
| `{:error, %{...}}` / `{:error, "reason"}` / any `other` | ExAws pass-through (`client.ex:97`) | `false` | suffixed |
| **raise** `ExAws.Error` (bad signature, bad bucket) | ExAws | n/a — propagates | upload crashes; no key is written |
| **raise** `KeyError`/`BadMapError` (`cdn_config.bucket` when `:cdn` is nil) | `cdn.ex:411` | n/a — propagates | upload crashes; no key is written |
| mock returns something exotic | test only | `false` | suffixed |

The two raise rows are the only non-`false` non-`true` outcomes, and they abort
before any presign or write. That is fail-closed by a different route, and it is
not a regression: the old `match?({:ok, _}, ...)` raised in exactly the same
places.

The residual risk the docstring names is the right one and is stated honestly: a
provider that answers an absent key with something other than 404 gets
`unique_filename/1` on **every** upload. That is a cosmetic/functional cost, not
a safety one — and `client.ex:83-87` already carries the matching "only a 404 is
translated" limit note. The two docs agree.

Caller inversion at `lib/brando/utils.ex:1182` is correct:
`if key_available?, do: key, else: unique_filename(key)` — the `true` branch is
now the narrow one.

Test coverage (`test/brando/utils_test.exs:524-568`) pins the branch that
matters: a 403 produces a suffixed key matching
`^media/images/site/logo/logo-[a-z0-9]+\.jpg$`. That assertion fails under the
old `match?({:ok, _}, ...)` implementation, so it is falsifiable.

### SUGGESTION — `build_upload_key/2` has no caller inside this repo

`lib/brando/utils.ex:1174`. Repo-wide grep (excluding `.claude/`) finds the
definition and the new tests, nothing else. It is public API on a library, so
consuming applications may call it — which is precisely why the fix is worth
having — but the guard being fixed is not on any code path Brando itself
executes today. Worth stating in the phase record so the change is not credited
with closing a live hole in this repo.

### SUGGESTION — `key_exists?/2` removal is a breaking public-API change

`Brando.CDN.key_exists?/2` was public and undeprecated. No `@deprecated`
shim was left. A downstream app calling it gets `UndefinedFunctionError` at
runtime, not a compile warning. Not a security issue; flag it in the changelog.

### Pre-existing (one line, outside the diff)

`get_valid_filename/2` (`utils.ex:1196`) honours `force_filename` with
`overwrite: true`, but `build_upload_key/2` then renames that filename whenever
the key is occupied — which under `overwrite: true` is the expected case. The
`overwrite` intent has never reached the key. Behaviour is unchanged by Phase 6.

---

## 2. `ReqOptions.merge/2` — `lib/brando/videos/uploaders/req_options.ex:30`

### Argument order: correct at all three call sites

| Site | Call | Order |
|---|---|---|
| `lib/brando/videos/uploaders/mux.ex:573` | `ReqOptions.merge(__MODULE__, request_opts)` | built second — wins |
| `lib/brando/videos/uploaders/bunny.ex:431` | `ReqOptions.merge(__MODULE__, request_opts)` | built second — wins |
| `lib/brando/videos/uploaders/cloudflare.ex:282-285` | `ReqOptions.merge(__MODULE__, [method:, url:, headers:] \|> maybe_put_json(body))` | built second — wins |

`Keyword.merge(configured || [], built_opts)` — in `Keyword.merge/2` the second
list wins on key collision, so `:headers`, `:url`, `:method` and `:json` as
built by each provider survive intact. The `__MODULE__` in each file is the
provider itself, so each reads its own config namespace; no cross-provider
config bleed.

`Req.request/1` is called in exactly three places in `lib/` — the three above.
There is no fourth transport site that skipped the helper.

The `nil`-as-absent handling (`Keyword.get(:req_options)` then `|| []`) is
correct and matters: `Application.put_env(mod, key, nil)` stores `nil`, and a
config-restore helper that does so would otherwise beat the `[]` default and
crash `Keyword.merge/2`.

### Credential leakage: none introduced

- `mux.ex:580,584`, `bunny.ex:438,442`, `cloudflare.ex:292,296` log
  `status`, the **response** body, and the error reason. None of those carries
  the request headers. `Req` transport errors (`Req.TransportError`,
  `Mint.TransportError`) hold a reason atom, not the request.
- The raise-on-missing-credentials messages (`mux.ex:545-551`,
  `bunny.ex:403-410`) print the *config key names* and the `System.get_env`
  call shape, never a value.
- `Req`'s own redirect step deletes the `authorization` header on a cross-host
  redirect (`deps/req/lib/req/steps.ex:1579`), so a redirect cannot walk the
  Bearer/Basic token to another host by default.

### WARNING — the docstring's guarantee is wider than `Keyword.merge/2` can deliver

**Severity**: WARNING
**Location**: `lib/brando/videos/uploaders/req_options.ex:18-20`
**Issue**: The doc says "The other direction lets a `:req_options` entry
silently replace the authorization header, the URL or the method — a config seam
that can unset credentials is a config seam that will." Keyword-level merge only
protects keys that the *built* options name. `Req` reaches the same
`authorization` header through a **different option key**, which never collides
and therefore always survives:

```elixir
# deps/req/lib/req/steps.ex:243
defp auth(request, {:bearer, token}), do: Req.Request.put_header(request, "authorization", "Bearer " <> token)
```

`put_header/3`, not `put_new_header/3` — it overwrites. Concrete failure:

```elixir
config :brando, Brando.Videos.Uploaders.Mux,
  access_token_id: {:system, "MUX_TOKEN_ID"},
  access_token_secret: {:system, "MUX_TOKEN_SECRET"},
  req_options: [auth: {:bearer, "attacker-token"}]
```

`merge/2` keeps `headers: [{"authorization", "Basic ..."}]` from the built list
*and* keeps `auth:` from config, because they are different keys. Req's `auth`
step then runs and replaces the header — exactly the outcome the merge order is
documented to prevent. The same non-colliding-key argument applies to `:adapter`
and `:plug` (redirect the authenticated request to arbitrary code, which is what
the seam is *for* in tests) and to `:params` (append query params to the built
URL). `:base_url` is harmless here — `put_base_url` no-ops when the request URL
already has a scheme (`steps.ex:122-125`), and all three providers build
absolute URLs.

**Exploit reality check**: the actor is whoever writes application config, who
already has arbitrary-code reach through `config/runtime.exs`. This is not a
privilege boundary. What is wrong is the *claim*, and a claim that overstates a
guard is how the guard later gets trusted for something it does not do.

**Fix** — pick one:

*(a) Narrow the doc (minimum, preferred):*

```elixir
Built values win **on keys the provider sets** — `:method`, `:url`, `:headers`,
`:json`. That is not a sandbox: `:req_options` is application config, and Req
reaches the same authorization header through `:auth`, and the same transport
through `:plug`/`:adapter`. What the merge order buys is that the *ordinary*
mistake — a config entry named `headers:` — cannot silently unset credentials.
```

*(b) Or make the mechanism match the claim, with an allowlist:*

```elixir
@transport_keys [:plug, :adapter, :retry, :retry_delay, :max_retries,
                 :receive_timeout, :connect_options, :pool_timeout]

def merge(provider, built_opts) do
  configured =
    :brando
    |> Application.get_env(provider, [])
    |> Keyword.get(:req_options)
    |> Kernel.||([])
    |> Keyword.take(@transport_keys)

  Keyword.merge(configured, built_opts)
end
```

(b) actually enforces "the seam is for the transport", which is what the
docstring argues. It would need `test/brando/videos/provider_client_test.exs` to
keep passing — the stub is installed through `plug:`, which is on the list.

### Test note (positive)

`test/brando/videos/provider_client_test.exs:363-383` is the right test: it
deliberately manufactures a `headers:` collision, because the `plug:`-only stub
used elsewhere produces the same list either way round and cannot see the merge
direction. It asserts the *decoded* `id:secret`, so a hijacked header fails
loudly. It does not cover the `:auth` gap above — that is what the WARNING is.

---

## 3. `mix.exs` package `files:` — no change to what ships

**Verdict: nothing new lands in the tarball.** The diff hunk
(`mix.exs:82-88`) replaces comment prose only; `files:` and all eight entries
are unchanged context. The `config`/`test` exclusion (and the removal of test
fixtures from the tarball) predates this diff.

The new comment's honesty about `priv/templates/brando.install/` shipping
placeholder credentials checks out. `.envrc.prod` contains
`<%= :crypto.strong_rand_bytes(64) |> Base.encode64 |> binary_part(0, 64) %>`
for `BRANDO_SECRET_KEY_BASE` and a generated DB password — EEx that is evaluated
at `mix brando.install` time, so the scaffold hands the operator a *fresh random*
secret, not a shared literal. That is better than the comment claims.
`deployment.cfg` and `fabfile.py` carry host/user placeholders only. No real
secret is in `priv/`.

### SUGGESTION — `"assets"` ships whatever is on disk, including `node_modules`

**Severity**: SUGGESTION (pre-existing; adjacent to the reviewed hunk)
**Location**: `mix.exs:90`
**Issue**: Hex packages from the filesystem, not from git. `assets/node_modules/`
exists locally (`.pnpm-workspace-state.json` et al.) and is `.gitignore`d, which
means it is invisible in review but included by the `"assets"` entry if present
when `mix hex.publish` runs. That is tarball bloat and an unaudited third-party
payload inside a package consumers trust.
**Fix**: add an explicit exclusion, so it cannot depend on the publisher's
working tree:

```elixir
files: [...],
exclude_patterns: ["assets/node_modules", "assets/dist"]
```

Worth a `mix hex.build && tar tzf brando-*.tar` before the next publish to
confirm what actually lands.

---

## 4. Remaining changed files — no security weight

- `test/support/live_case.ex:128,148` — `kill_live/2`'s `role` argument and
  `await_proxy_exit/1` flunking instead of returning `:ok` on a live proxy.
  Test-harness correctness; no production reach. The `flunk` now happens
  *before* `Process.flag(:trap_exit, prior_trap?)` is restored, which the new
  `restore_trap_exit/0` helper in the test file works around. Acceptable —
  a real flunk ends the process — but a `try/after` around the wait would be
  tidier than a helper the caller has to remember.
- `test/brando/plugs/lockdown_test.exs:7` — `async: false`. Strictly
  correct: the tests mutate `:brando, :lockdown*` global env.
- `test/brando/utils_test.exs`, `test/brando/videos/provider_client_test.exs`,
  `test/brando_admin/live/form_recovery_test.exs` — tests only.
- `lib/brando/cdn/client.ex:29`, `e2e/e2e/playwright/utils.js:12-18` — comment
  text only.

Checked across the diff for the standing Iron Laws: no `String.to_atom` on
external input, no `raw/1`, no string interpolation into queries or fragments,
no `binary_to_term`, no new unauthorized `handle_event`, no hardcoded secret.
All clean.

---

## Recommendations, in priority order

1. Narrow the `ReqOptions.merge/2` docstring, or add the `Keyword.take/2`
   allowlist so the mechanism matches the claim (`req_options.ex:18-20`).
2. Add `exclude_patterns: ["assets/node_modules"]` to `package/0` and verify
   with `mix hex.build` before the next publish (`mix.exs:89`).
3. Note the `key_exists?/2` removal in `CHANGELOG.md` — it is a breaking change
   to a public function on a library.
4. Record in the phase log that `build_upload_key/2` has no in-repo caller, so
   the overwrite fix is a library-consumer fix rather than a live-hole closure.

## Tools to run manually (this agent has no Bash access)

- `mix sobelow --exit medium`
- `mix deps.audit`
- `mix hex.audit`
- `mix hex.build && tar tzf brando-*.tar | grep node_modules`
