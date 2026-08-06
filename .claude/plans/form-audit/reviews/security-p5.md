# Security Review — Phase 5 (`git diff HEAD~6`, base 5ed8aa885)

Scope: the six Phase 5 commits. Verdict: **no BLOCKER.** Every change in the
diff is neutral-or-better for security. Three items below are worth acting on;
two of them are pre-existing behaviour that this diff's own comments now
codify, which makes them fair to raise here.

---

## 1. `mix.exs` — dropping `config` and `test` from the hex package

**No finding. The change is correct and the stated rationale checks out.**

Verified independently of the comment:

- Mix compiles dependencies in `:prod` regardless of the parent's `MIX_ENV`, so
  `elixirc_paths(:test) -> ["lib", "test/support"]` (mix.exs:54) can never fire
  for `:brando` as a dep. `test/support` was dead weight in the tarball.
- Elixir has not evaluated dependency `config/*.exs` for many major versions.
  `config/test.exs` was inert in a consumer.

**Did a real key ever ship?** I cannot answer this with the tools I have — no
Bash, so no `git log -p config/test.exs` and no way to fetch published hex
tarballs. **This is the one open item that needs a human with a shell.** The
check is cheap and worth doing once:

```
git log -p --follow -- config/test.exs | grep -inE 'AKIA|sk-|xox[baprs]-|-----BEGIN|secret_access_key|api_key|token'
```

What I *can* say about the current tree: `config/test.exs` contains
`secret_key_base: String.duplicate("verysecret", 8)` (line 74) and
`signing_salt: "testsigningsalt"` (line 75) — obvious placeholders, not
credentials, and a DB URL of `postgres:postgres@localhost` (line 61). If the
history check comes back clean, nothing needs rotating. Note the blast radius
even if it were dirty: these were the *test integration endpoint's* salts, not
anything a consuming app would ever run under.

### SUGGESTION — the mix.exs comment's argument does not survive contact with `priv`

`mix.exs:75-85` justifies the removal as "a standing invitation for a real key
to be added to a file nobody thinks of as published". That reasoning applies
verbatim to `priv`, which still ships and still contains
credential-shaped placeholders:

- `priv/templates/brando.install/deployment.cfg:8,13` — `DB_PASS =
  prod_database_password`, `SSH_PASS = sudoer_pass`
- `priv/templates/brando.install/fabfile.py:968` — an rclone config template
  with `access_key_id`/`secret_access_key` interpolation
- `priv/templates/brando.install/.envrc.prod:3` and `.envrc:3`,
  `config/brando.exs:43` (`lockdown_password`)

These *must* ship — they are the generator's payload — so this is not a bug.
But the file that most invites an accidental real key is `deployment.cfg`,
because it is the one a developer edits with real values for their own project
and could paste back. Consider trimming the comment's claim to what it
actually establishes ("these two were shipped and never evaluated; dropping
them also removes the test fixtures") rather than a general secrets argument
that `priv` contradicts.

Also confirmed: nothing in `assets`, `guides`, `README.md`, `CHANGELOG.md`,
`UPGRADE.md` carries credential-bearing content. No consumer breakage from the
removal — `test/support` was never compiled for a dep, so no application can
have been importing `Brando.ConnCase`/factories from the hex build.

---

## 2. `lib/brando/cdn/client.ex:96` — `{:http_error, 404, _} -> {:error, :not_found}`

**No authorization or ownership decision changes.** I traced every caller:

- `Brando.CDN.key_exists?/2` (cdn.ex:381) — `match?({:ok, _}, ...)`. A 404
  produced `false` before the change and produces `false` after. Unchanged.
- `Brando.Uploads.finalize_direct/3` (uploads.ex:266, 292) — a 404 previously
  fell through the catch-all `{:error, reason}` clause and surfaced a raw ExAws
  tuple; it now hits `{:error, :not_found}` and surfaces "Uploaded object not
  found in bucket". Both are failures. Nothing that was rejected is now
  accepted.
- `lib/mix/tasks/brando.files.update_content_disposition.ex:111` calls
  `ExAws.S3.head_object` directly and does not go through this seam at all.

**Can 403 now be masked as "not found", or used to probe the bucket?** No, in
both directions:

- 403 is *not* translated — it still falls through as `{:error, {:http_error,
  403, _}}` and reaches the operator, so a permission failure is not disguised.
- Probing requires attacker control of `key`. It has none.
  `upload_manager.ex:475-486` builds `finalize_params` from `item.direct.key`,
  which comes from intake, not from the `direct_complete` event
  (upload_manager.ex:472-474), and `finalize_orphaned_complete/3`
  (upload_manager.ex:507-519) rejects a ref whose recorded `creator_id` is not
  the calling user. There is no path from a request parameter to this `key`.

### WARNING — the documented 403 limit lets a HEAD failure silently overwrite an existing object

`lib/brando/cdn/client.ex:84-86` records the known limit that a 403 is not
translated. That limit has a consequence one caller away that the note does not
mention, and it is not the `finalize_direct` branch:

`Brando.Utils.build_upload_key/2` (`lib/brando/utils.ex:1182`) uses
`key_exists?/2` as an *overwrite guard* — if the key exists it appends a unique
suffix, otherwise it hands the bare key to the presigner. `key_exists?/2`
collapses **every** error to "does not exist". So on a bucket policy that
answers HEAD for an *existing* key with 403 (no `s3:GetObject` on the HEAD
principal — a normal least-privilege setup on R2/Spaces/MinIO), the guard
returns `false` for a key that is present, Brando presigns a PUT to that exact
key, and the browser's upload **replaces the bytes of an existing asset** while
that asset's DB row still points at the key. The old asset's content becomes
whatever the new uploader sent, under the old asset's title, creator and
permissions.

Pre-existing, not introduced by this diff — but the diff is where the 403 gap
got written down, so this is the right moment to write down what it costs.

Concrete fix (does not require translating 403):

```elixir
# lib/brando/cdn/cdn.ex:381
def key_exists?(object_key, field_cfg) do
  case head_object(object_key, field_cfg) do
    {:ok, _} -> true
    {:error, :not_found} -> false
    # Anything else is "we do not know" — treat as taken. A spurious unique
    # suffix costs nothing; a wrong `false` overwrites a live asset.
    {:error, _other} -> true
  end
end
```

This is exactly the value the new `:not_found` translation makes expressible —
before it, `key_exists?/2` had no way to tell "absent" from "cannot tell".

### SUGGESTION — raw ExAws errors reach the operator UI

`uploads.ex:283` / `:308` pass `{:error, reason}` through untouched, and
`upload_manager.ex:129` logs it. For a non-404 S3 failure `reason` is the ExAws
tuple including the S3 error XML — bucket name, region, request id, and
sometimes the endpoint. Admin-only surface and low value to an attacker, but
the 404 case now gets a clean operator message while the others do not; worth
the same treatment.

---

## 3. `mux.ex:579`, `bunny.ex:437`, `cloudflare.ex:284-287` — `Keyword.merge` order

**Confirmed: this closes an override path and opens nothing.** With
`Keyword.merge(req_options(), request_opts)` the built list wins, so
`:method`, `:url`, `:headers` (and `:json` where present) are no longer
settable from `config :brando, Brando.Videos.Uploaders.Mux, req_options: [...]`.
Previously a `req_options: [headers: [...]]` entry replaced the whole header
list including `authorization` — that is the hole, and it is shut. Cloudflare
now matches Mux and Bunny.

**Does it break a legitimate use?** Checked what is left overridable: `:plug`,
`:adapter`, `:retry`, `:connect_options`, `:receive_timeout`, `:decode_body`,
`:finch` are all untouched by the built list, so `Req.Test` stubbing still works
(`test/brando/videos/provider_client_test.exs`) and so do timeout/proxy tweaks.
`:base_url` is now moot but harmlessly so — the built `:url` is absolute
(`mux.ex:539`, `bunny.ex:398`, `cloudflare.ex:274`), so `:base_url` never
applied even before the change.

One real consequence: `req_options: [headers: [...]]` is now **silently
dropped** rather than honoured, so an operator adding a tracing or egress-proxy
header gets no error and no header. That is the correct security trade, but it
is a silent one — worth a line in the `req_options` docs, or merging `:headers`
specifically while keeping `authorization` built-side.

### SUGGESTION — `:auth` still overrides the authorization header

The comment on `mux.ex:576-578` / `bunny.ex:434-436` / `cloudflare.ex:280-282`
claims "a config seam that can unset credentials is a config seam that will".
It still can, through a different key. Req's `auth` step
(`deps/req/lib/req/steps.ex:227-245`) runs as a *request step*, after the
options are assembled, and uses `Req.Request.put_header/3` — an overwrite, not
a `put_new_header`. So:

```elixir
config :brando, Brando.Videos.Uploaders.Mux,
  req_options: [auth: {:bearer, "anything"}]   # still wins over the built header
```

`Keyword.merge` cannot stop this, because `:auth` and `:headers` are different
keys. Low severity — `req_options` is operator config, not user input, so this
is defence-in-depth against a footgun rather than an attack path. If you want
the comment's claim to be true, drop the reserved keys explicitly:

```elixir
request_opts =
  req_options()
  |> Keyword.drop([:auth])
  |> Keyword.merge(request_opts)
```

---

## 4. `lib/brando/blueprint/error_translator.ex:62-66` — the replaced `Logger.error`

**Clean.** `Forms.list_fields/1` (`lib/brando/blueprint/forms.ex:496-502`)
comprehends `input.name` out of tabs → fieldsets → inputs. It returns **field
name atoms from the compile-time blueprint DSL** — schema shape, not entry
data. `name` on `%Forms.Form{}` is likewise a DSL-declared atom. Neither can
carry a user value or a secret.

This is a strict improvement on what it replaced: `inspect/1` of the whole
`%Forms.Form{}` also serialised every input's `opts`, which is where blueprints
put defaults and option lists and where an application could plausibly have put
something sensitive.

The old call is genuinely gone — `Logger.error` appears exactly once in the
file, at line 63, and it is the new one.

---

## 5. `config/test.exs` — comment-only change

Confirmed comment-only. The added block (lines 7-17) documents the Mox seam and
names `cdn.ex:311,354,362` as deliberately outside it. No credential
introduced; the placeholders at lines 61, 74, 75 are unchanged from before the
diff.

---

## 6. `test/support/support.ex:29-39` — `put_test_env/2`

**Not a production path, and the helper itself is a fix, not a regression.**
`Application.fetch_env/2` + `delete_env/2` correctly restores "key was absent",
which the hand-rolled `get_env`/`put_env` pattern it replaces got wrong — that
bug leaked a stored `nil` across files and broke unrelated tests. `on_exit`
runs even when an assertion fails, which the old inline teardown did not.

### WARNING — `async: true` + global app env is a genuine cross-module leak

`test/brando/plugs/lockdown_test.exs:2` is `async: true` and every test in it
sets `:lockdown` globally (lines 100, 127, 147, 166, 179). `Application.put_env`
is VM-global; `async: true` only serialises tests *within* a module. So for the
duration of those tests, `Brando.config(:lockdown)` is `true` for every
concurrently running test module.

Concrete failure: any async test that drives a request through a pipeline
containing `Brando.Plug.Lockdown` gets a 302 to `/coming-soon` instead of its
expected response, intermittently, depending on scheduling. Today nothing else
in `test/` mounts that plug, so the bug is latent rather than active — but it
is latent in the direction where *adding* a test later makes an unrelated,
already-passing test flaky, and the failure will look like a bug in the new
test.

The security-control-disabled variant is the one that does *not* apply here:
`lockdown_test.exs:116` sets `:lockdown, false` mid-test, but the only assertion
that depends on lockdown being on lives in the same module, which runs
serially. No security assertion elsewhere can be silently switched off.

Fix is one word — `use ExUnit.Case, async: false` on this module, with the
reason stated (it mutates global application env). Same applies to any other
`put_test_env` caller in an async module; `test/brando/videos/upload_test.exs`,
`test/brando/uploads_test.exs`, `test/brando/utils_test.exs`,
`test/brando/html_test.exs`, `test/brando/uploads/direct_finalize_test.exs` and
the two form component tests are worth the same check.

---

## 7. Migrations — no constraint weakened

- `20260806000001_unique_block_uid_in_test_schema.exs:37` — **adds**
  `unique_index(:content_blocks, [:uid])`. Strictly tightening, and it makes
  the existing `unique_constraint(:uid)` in `Block.block_changeset/3` reachable
  instead of silently inert. Two root blocks could previously share a uid,
  which the block store, DOM ids (`block-<uid>`) and recovery keys
  (`entry_block_form-<uid>`) all assume cannot happen.
- `20160219000000_test_migrations.exs:295-326` — `content_blocks.uid` stays
  nullable, matching production (`brando_103` install + `brando_123` unique
  index, neither of which adds `null: false`). Deliberate, documented at
  lines 296-307, and correct: making the fixture *stricter* than production
  hides bugs the same way making it looser does.
- `content_refs.uid` remains `null: false` with `unique_index`
  (lines 336, 358), matching `brando_137`. All `references(...)` on_delete
  behaviours in the touched region are unchanged.

Nothing here relaxes a NOT NULL, drops an index, or loosens an FK.

---

## Pre-existing issues outside the diff (one line each)

- `lib/brando/plugs/lockdown.ex:57` — `key == pass` is a non-constant-time
  compare of the lockdown password, and the password travels in the query
  string (`?key=<pass>`), so it lands in access logs, `Referer` headers and
  browser history.
- `lib/brando/utils.ex:1182` — overwrite guard treats every `head_object` error
  as "key absent"; see §2 WARNING.
- `priv/templates/brando.install/lib/application_name_web/controllers/lockdown_controller.ex:11`
  — hashes the configured lockdown password with a fresh salt on every request
  and immediately verifies against it, so `Bcrypt.verify_pass/2` can only ever
  return true for the configured value; it works, but it is a bcrypt round of
  latency per request and reads as if it were comparing against a stored hash.
- `lib/brando/uploads.ex:283,308` — raw ExAws error tuples reach the operator
  UI; see §2 SUGGESTION.

---

## Checked and clean

`String.to_atom` on user input, `raw/1` with untrusted content,
`binary_to_term`, SQL interpolation in fragments, CSRF pipeline config,
hardcoded secrets in `lib/` — no findings in the Phase 5 diff.

## Needs a shell (I have no Bash)

1. `git log -p --follow -- config/test.exs` grepped for real key material —
   the one unanswered question from §1.
2. `mix hex.build` then inspect the tarball to confirm the `files:` list
   produces what is intended.
3. `mix sobelow --exit medium`, `mix deps.audit`, `mix hex.audit`.
