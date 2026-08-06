# Code Review: Phase 6 (`git diff HEAD~5`) — Elixir idioms

## Summary
- **Status**: ⚠️ Changes Requested (two WARNINGs, both about claims/consumer
  visibility rather than runtime behaviour; the code changes themselves are
  correct)
- **Issues Found**: 5 (0 blocker, 2 warning, 3 suggestion)

The three things you asked to be checked come back clean:

1. **`key_available?/2` is equivalent-or-safer at its call site.** Old:
   `match?({:ok, _}, head_object(...))` → `true` only on a hit → rename.
   New: `head_object(...) == {:error, :not_found}` → `true` only on a
   definitive absence → use bare key. The rename set is now a strict superset
   of the old one (`{:ok,_}` ∪ every other error), so the only behaviour delta
   is *more* renaming, never less overwriting. `utils.ex:1182` reads correctly:
   `key_available?` is true exactly when writing the bare key is safe, and the
   one-liner `do: key, else: unique_filename(key)` matches the predicate's
   name with no double negative.
2. **`ReqOptions.merge/2` is a faithful extraction.** All three providers'
   `get_config/1` are byte-identical
   (`Application.get_env(:brando, __MODULE__, []) |> Keyword.get(key)` —
   `mux.ex:589`, `bunny.ex:447`, `cloudflare.ex:305`), and `merge/2` reproduces
   exactly that with `provider` substituted for `__MODULE__`, then
   `Keyword.merge(configured || [], built_opts)`. Mux/Bunny previously had
   `Keyword.merge(req_options(), request_opts)`; Cloudflare had the inline
   form. Same precedence direction (built wins) at all three sites, `nil`
   handling preserved. No drift.
3. **Public-API removal**: real but low-risk — see WARNING 2.

W4's scope (merge only, no `api_request` collapse), the no-default-arg
`kill_live/2`, and `|| []` over `Keyword.get/3` default are all delivered as
argued; not re-litigated.

---

## Warnings

### WARNING 1 — `build_upload_key/2` has no in-repo caller, so "this is a production upload path" is unverified
`test/brando/utils_test.exs:515-522`, `lib/brando/utils.ex:1174`

A repo-wide grep for `build_upload_key` returns only its own definition and the
three new tests. Nothing in `lib/` calls it — the direct-upload path presigns
through `Brando.Uploads` (`uploads.ex:266,292` call `CDN.head_object/2`
directly). So `key_available?/2` currently has **zero** production callers
inside Brando; its only exercise is a downstream app calling
`Brando.Utils.build_upload_key/2` itself.

That does not make the fix wrong — fail-closed is still the right default for a
public library helper — but two claims now outrun the code:

- the plan's "This is a production upload path, so the standard applies at full
  strength" (`phase-6-plan.md:196`), and
- the new test comment's "`build_upload_key/2` decides whether an upload writes
  to the key it wants or to a renamed one".

Both are true *of a consumer*, not of this repo. Either say so ("the only
caller is downstream; in-repo this is library surface"), or — better — check
whether `build_upload_key/2` is dead surface that should be either wired into
the upload path or removed. Given the codebase's own standing rule (remove dead
code when found), an unused public helper guarded by a live S3 `HEAD` is worth
a deliberate answer rather than a silent keep.

### WARNING 2 — a removed public function on a published library, with no CHANGELOG entry
`lib/brando/cdn/cdn.ex:397`, `CHANGELOG.md:1-3`

`Brando.CDN.key_exists?/2` was public (no `@doc false`) on a hex-published
library, and is gone rather than deprecated. The plan's risk assessment is
sound — no `@doc`, no `guides/`/`priv/` reference, one internal caller — but
the mitigation was never written down where a consumer would look. `CHANGELOG.md`
has an active `## 0.54.0 (Unreleased)` section with detailed prose for far
smaller changes, and this removal is not in it.

Suggested: one line under Unreleased →
`Brando.CDN.key_exists?/2` removed, replaced by `key_available?/2` (inverted
sense, and now fail-closed: only `{:error, :not_found}` frees a key). Callers
inverting the branch is a mechanical change; callers *not* noticing get a
`function undefined` at compile time, which is the good failure — the
CHANGELOG line is what turns that into a two-minute fix instead of a bisect.

Alternatively `@deprecated "Use key_available?/2 (note: inverted)"` on a
one-release shim. The removal is defensible; the silence about it is not.

---

## Suggestions

### SUGGESTION 1 — `kill_live/2` leaves `trap_exit` on when it flunks
`test/support/live_case.ex:120-134`

Both `flunk` sites (the 1s `{:DOWN, …}` timeout and the new 500ms
`await_proxy_exit/1`) raise before `Process.flag(:trap_exit, prior_trap?)`.
Phase 6 *adds* a flunk path here, and the test file has to hand-roll
`restore_trap_exit/0` (`form_recovery_test.exs:301`) to work around it. The
comment at `live_case.ex:114-117` explains why the flag must be restored — that
argument applies to the failing path too, and a `try/after` would make it
unconditional:

```elixir
try do
  Process.exit(pid, :kill)
  # … receives, and `if role == :root, do: await_proxy_exit(proxy_pid)`
after
  Process.flag(:trap_exit, prior_trap?)
end
```

Low impact (a flunk usually ends the test process anyway) and the test comment
is honest about it, so this is a suggestion — but it would delete the
`restore_trap_exit/0` helper, which exists only to paper over the gap.

### SUGGESTION 2 — precedence is pinned for Mux only
`test/brando/videos/provider_client_test.exs:362-384`

The new test proves the rule for `Mux`. Bunny's and Cloudflare's call sites are
not covered by anything that would fail if one of them stopped calling
`ReqOptions.merge/2` and inlined a flipped `Keyword.merge/2` again. Argument
*order* is protected by the signature (an atom where a keyword list is expected
crashes loudly), so the residual risk is only "a provider drops the helper" —
small, but the whole point of W4 was that a silent per-provider drift is what
happened before. One extra assertion in each of the existing Bunny/Cloudflare
request-shape tests (a configured `headers:` entry that must lose) would close
it cheaply.

### SUGGESTION 3 — `ReqOptions.merge/2` re-implements each provider's `get_config/1`
`lib/brando/videos/uploaders/req_options.ex:219-226`

The helper reads `Application.get_env(:brando, provider, [])` itself rather
than being handed the value. That is what makes the call sites a one-liner, and
it is fine today because all three `get_config/1` bodies are identical — but it
means the merge no longer goes through the provider's own config accessor. If a
provider later reads credentials/options from somewhere else (system env, a
runtime store), `:req_options` would silently keep coming from app env only.
An alternative that keeps the precedence rule as the single owned thing without
owning config lookup:

```elixir
def merge(configured, built_opts), do: Keyword.merge(configured || [], built_opts)
# call site: ReqOptions.merge(get_config(:req_options), request_opts)
```

Judgement call — the current shape has fewer moving parts at three call sites.
Noted, not insisted on.

---

## Verified-clean, listed so the absence is deliberate

- `key_available?/2` is `==` against a two-element tuple, not `match?` — so a
  future `{:error, :not_found, meta}` shape would silently flip to "occupied"
  (the safe direction). Correct as written.
- New `utils_test.exs` cases run under `async: false` (`utils_test.exs:2`) with
  `verify_on_exit!`, so the Mox expectations are process-owned and safe.
- `stub_view_with_live_proxy/0` returns a bare map, not `%View{}`; `kill_live/2`
  only reads `.pid`/`.proxy`, so no struct pattern is bypassed. The `:child`
  test's 400ms budget against a 500ms wait is a real (if slim) discrimination.
- `lockdown_test.exs` `async: false` is correct for global app-env mutation.
- E2E/`mix.exs`/`client.ex` comment edits are prose only and match the code
  they describe (`ReqOptions` module now exists; `Mux.req_options/0` no longer
  does, so the old cross-reference would have dangled).

## Pre-existing, outside the diff (one line each, per scope)

- `lib/brando/utils.ex:1196` — `force_filename` + `overwrite: true` still gets a
  unique suffix when the key is occupied, which reads as contradicting
  `overwrite: true`. Unchanged by this diff (the old predicate renamed on a hit
  too); fail-closed only widens when it fires.
- `lib/brando/cdn/cdn.ex:411` — `cdn_config.bucket` raises on a `field_cfg`
  without a `:cdn` map; already flagged in `iron-laws-p4.md:72`. PERSISTENT.
- `lib/brando/videos/uploaders/cloudflare.ex` vs `mux.ex`/`bunny.ex` — missing
  credentials return `{:error, :not_configured}` vs raise. Recorded as
  deliberately out of scope in the plan; noted only so it is not lost.
