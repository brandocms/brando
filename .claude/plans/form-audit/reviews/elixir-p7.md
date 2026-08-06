# Code Review: form-audit Phase 7 (working tree, branch `next`)

## Summary
- **Status**: ⚠️ Changes Requested
- **Issues Found**: 2 WARNING, 4 SUGGESTION, 0 BLOCKER

Phase 7's own standard is that a cited line is checkable. Two citations added by
this phase are off by one, and one @doc's bullet list of "what reaches past the
merge" is materially incomplete in a way the accompanying new test makes look
authoritative. Everything else I could falsify checked out.

---

## Verified correct (claims I tried to break and could not)

- `req/steps.ex:236, 240, 244` — `auth/2` binary / `{:basic, _}` / `{:bearer, _}`
  clauses all call `Req.Request.put_header/3`. Exact, req 0.7.2
  (`deps/req/mix.exs:4`). The "overwrites, not `put_new_header`" claim holds.
- `req/steps.ex:123` — `if request.url.scheme != nil do request` inside
  `put_base_url/1`. The "`:base_url` no-ops on absolute URLs" claim is exact.
- "All three providers build `:method`, `:url` and `:headers` (plus `:json` on a
  body)" — `mux.ex:563-570`, `bunny.ex:421-428`, `cloudflare.ex:284` +
  `maybe_put_json/2` (`:302-303`). True at all three sites.
- `client_proxy.ex:542-545` — `handle_info({:DOWN, …})` → `fetch_view_by_pid/2`
  → `{:stop, reason, state}`. Exact.
- `mix.exs:93` — "generator templates … live under `priv/templates/`". True:
  `priv/templates/brando.gen/`, `brando.gen.otel/`, `brando.install/` all
  present and all inside the shipped `"priv"` entry.
- `utils.ex:1189` `Map.get(file_cfg, :overwrite, false)` — `file_cfg` is a map
  or `%Brando.Type.FileConfig{}` on every path that reaches here:
  `concat_with_upload_path/2` already does `Map.get(file_cfg, :upload_path)`
  (`:1197`) and `get_valid_filename/2` head-matches `%{force_filename: …}`
  (`:1206`). A keyword list would already have died two lines earlier,
  pre-existing. Not a new hazard.
- **Ordering with `force_filename` / `random_filename` is right.**
  `get_valid_filename/2` runs first and resolves the name
  (`force_filename` under `overwrite: true` → `random_filename` → slugify); the
  new `cond` then only decides *uniquify or not*. So `overwrite: true` +
  `force_filename` now yields the forced name verbatim
  (`utils_test.exs:577-581` pins it).
- **The three-way agreement claim holds for `overwrite`.**
  `upload.ex:321-325`: `if Map.get(cfg, :overwrite), do: joined_dest`.
  `uploads.ex:427-428`: `Map.get(cfg, :overwrite, false) -> maybe_slugify(…)`,
  no `unique_filename`. `utils.ex:1189`: short-circuit. All three now skip the
  uniquify under `overwrite`. Under `random_filename` all three also agree
  (unique name, no suffix). CHANGELOG:69-80 describes this accurately.

---

## Warnings

### W-1 — `live_case.ex:97, 98` — both new line citations are off by one

The `@doc` S-2 added says:

> `put_view/3`, `client_proxy.ex:848` … keys them all in one `state.pids` map
> (`:856`)

Against the vendored **phoenix_live_view 1.2.8**:

| Doc says | Actual |
|---|---|
| `:848` = `Process.monitor(pid)` | **`:849`**. `:848` is `new_view = %{view \| module: module, …}` |
| `:856` = `pids: Map.put(state.pids, pid, …)` | **`:857`**. `:856` is `views: Map.put(state.views, …)` |

Both cited lines exist and say something plausible-but-different — `:848`
builds the view struct, `:856` writes the *views* map — which is the failure
mode that is hardest to catch on a re-read. The phase-7 plan (`:147`) records
this as a *correction* to the plan's original `:849` ("the monitor is on
`:848`"); the correction went the wrong way. `defp put_view/3` is at `:846`,
so citing the function head would be robust against exactly this.

`:908-912` for `fetch_view_by_pid/2` is a one-line-early range (`defp` is at
`:909`) — harmless, mentioned only for the same fix. I did not open `:1001`.

**Fix**: `:848 → :849`, `:856 → :857`, or cite `put_view/3` at `:846`.

### W-2 — `req_options.ex:29-41` — "What still reaches past it" reads exhaustive and is not

The section opens by saying the merge is not an allowlist and "several of those
change the same request state by another route", then gives a closed bullet
list: `:auth`, `:plug` / `:adapter`, `:params`. `:base_url` is then singled out
as safe. A reader takes that as "these four reach past, and `:base_url` is the
one that looks dangerous but isn't" — and `req_options_test.exs:74-96` pins
exactly those four, which reinforces the reading.

Concretely absent, all real in req 0.7.2 and all reaching past the merge:

- **`:json` / `:body` / `:form` / `:form_multipart`** — the sharpest one. The
  providers only build `:json` on a body request; `mux.ex:564` (`:get`) and
  `:570` (`:delete`) build no body key at all, so a configured
  `req_options: [json: %{…}]` attaches a body to *every* GET and DELETE the
  provider makes. This is the same class as `:auth`, on a key the built
  options *sometimes* name — the one case the "exactly the keys `built_opts`
  names" framing cannot express.
- **`:connect_options`** — e.g. `transport_opts: [verify: :verify_none]`
  disables TLS verification for credentialed requests. Security-relevant, and
  strictly worse than anything on the list.
- **`:redirect`, `:retry`, `:decode_body`, `:into`, `:finch`,
  `:receive_timeout`, `:path_params`** — each changes what the request does or
  how many times it happens.

This is the defect class Phase 7 exists to close: the previous version of this
doc claimed more than the code did, and the rewrite now claims *less* than the
code does while looking complete.

**Fix** (prose only, no behaviour change): say the list is illustrative, not
exhaustive — "any key the built options do not name reaches Req unchanged;
the ones most likely to surprise are …" — and add the `:json`-on-a-GET case,
since it is the one a reader of "exactly the keys `built_opts` names" would
positively conclude is impossible.

---

## Suggestions

### S-1 — `cdn.ex:92, 124` — bare-string `raise` is in-house style, but the `:default` message is misleading

`raise "…"` with a bare string is consistent with this tree (98 `raise`
occurrences across 40 files in `lib/brando/`, overwhelmingly bare strings or
heredocs — e.g. `cdn.ex:378-384` right above). No objection to the form.

Two notes on content:

1. `:92` says "Either insert a custom config under the `s3` key, **or set
   `Brando.CDN.S3Config`**". The clause head is
   `%{cdn: %{enabled: true, s3: :default}}` — the config author reached this by
   *writing* `s3: :default`, so "insert a custom config under `s3`" means
   replacing `:default`. That reads fine. The `:124` message is accurate.
2. `:124`'s guard does not cover the shape the comment implies it does. The
   comment (`:117-122`) is about `nil`. But `config(Brando.Images, :s3)` can
   also return a **keyword list** — `Brando.Uploads.normalize_cdn_config/1`
   (`uploads.ex:385-389`) exists precisely because "app configs may give the
   CDN config as a struct, plain map or keyword list". A keyword list is
   truthy, passes `if !s3_config`, and then dies in `Map.from_struct/1` with
   `BadStructError` / `no function clause` — the same uninformative failure the
   raise was added to remove, one shape over. Consider
   `unless is_struct(s3_config, Brando.CDN.S3Config)` (same at `:104-112`,
   which has no guard at all and takes `s3_config` straight from user config).

### S-2 — `req_options_test.exs:74-96` pins keyword survival, not the documented consequence

The test asserts `:auth` etc. *survive the merge*. The doc's actual claim is
stronger — that `:auth` **overwrites** the provider's `authorization` header
downstream. That claim rests on `req/steps.ex:236-244`, a moving dep, and
nothing in the suite goes RED if req switches to `put_new_header/3`. The
provider tests already have `Req.Test` plumbing (`provider_client_test.exs:52`);
one request through it with `auth:` configured would make the doc's real claim
falsifiable rather than its keyword-level proxy. Cheap, and the same argument
S-2 (version pin) makes for `client_proxy.ex`.

### S-3 — `req_options.ex` has no `@spec`, and `merge/2` is the module's whole public surface

Two-line function, one public callee, three call sites. `@spec merge(module(),
keyword()) :: keyword()` costs nothing and lets Dialyzer see the `|| []`.

### S-4 — `mix.exs:79-99` — the comment is accurate but now argues two unrelated things

The `config`/`test` exclusion rationale (`:79-90`) and the `assets/` removal
(`:91-99`) are stacked without a break, so the "Not claimed here:" paragraph
about `priv/` credentials sits between them and reads as if it qualifies the
`assets/` decision. Both claims are true — I verified `priv/templates/` and the
absence of `"assets"` from `files:` — this is purely about which paragraph
attaches to which. A blank-line-separated second block, or a leading
`# assets/`, fixes it.

---

## Pre-existing

- `lib/brando/utils.ex:1202` — `get_valid_filename("", _)` returns
  `{:error, :empty_filename}`, which `concat_with_upload_path/2` then passes to
  `Path.join/2`; the tagged tuple never reaches a caller as an error.
- `lib/brando/cdn/cdn.ex:104-112` — `get_s3_config(%{cdn: %{s3: s3_config}})`
  calls `Map.from_struct/1` on unvalidated app config (see S-1.2).
- `lib/brando/uploads.ex:419-421` — the comment claims
  `build_direct_filename/2` mirrors the server pipeline; it does not honour
  `force_filename` at all, and slugifies only under `slugify_filename`, where
  `get_valid_filename/2` always slugifies in its default branch. Same claim
  class as this phase's remit, but untouched by it.
- `lib/brando/videos/uploaders/cloudflare.ex:272-273` — returns
  `{:error, :not_configured}` where Mux and Bunny raise. Already carried in the
  plan (`phase-7-plan.md:390-394`); fourth recording.
