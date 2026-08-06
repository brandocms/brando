# Code Review: Phase 4 — LiveView harness + production fixes (HEAD~5..HEAD)

## Summary
- **Status**: ⚠️ Changes Requested
- **Issues Found**: 2 BLOCKER, 6 WARNING, 5 SUGGESTION, 3 pre-existing one-liners

---

## Critical Issues

### BLOCKER 1 — `Brando.CDN.Client` documents an error shape its real impl never returns

`lib/brando/cdn/client.ex:44`

```elixir
@doc "Fetch object metadata. `{:error, :not_found}` when the key is absent."
@callback head_object(bucket :: binary, key :: binary, s3_config) ::
            {:ok, map} | {:error, term}
```

The real implementation does no translation at all:

```elixir
# lib/brando/cdn/client.ex:71-75
def head_object(bucket, key, s3_config) do
  bucket |> ExAws.S3.head_object(key) |> ExAws.request(s3_config)
end
```

ExAws never produces `{:error, :not_found}`. Verified in
`deps/ex_aws/lib/ex_aws/request.ex:9,160,165,204`:

```elixir
@type error_t :: {:error, {:http_error, http_status, binary}}
...
{:error, {:http_error, status, error}}
```

A missing key on HEAD comes back as `{:error, {:http_error, 404, _}}`.

Consequence — the callers branch on the documented shape:

```elixir
# lib/brando/uploads.ex:282
{:error, :not_found} -> {:error, "Uploaded object not found in bucket (#{key})"}
{:error, reason}     -> {:error, reason}
```

and the new test stubs exactly the documented shape:

```elixir
# test/brando/uploads/direct_finalize_test.exs:131
expect(Client.Mock, :head_object, fn _, _, _ -> {:error, :not_found} end)
```

So the "object never landed" branch is now covered by a test **for a case
production cannot reach**. In production a missing key falls through to
`{:error, reason}` and the raw `{:http_error, 404, %{...}}` tuple is surfaced
where a user-facing string is expected. The seam was introduced specifically to
make this path testable; as written it makes the test green while leaving the
production branch dead. The same applies to `delete_object`'s doc claim
(`client.ex:48`, "S3 DELETE is idempotent, so a missing key succeeds") — true of
S3 itself, so that one is harmless, but it is stated as a *contract of the
callback* which the ExAws impl also does not enforce.

Either the behaviour must normalise 404 → `:not_found` in `Client.ExAws`, or the
`@doc` and the mock must speak ExAws's actual tuple. Right now the two disagree
and only the mock is exercised.

### BLOCKER 2 — "Every runtime S3 call goes through `Brando.CDN.Client`" is false

`config/test.exs:7-9`

```elixir
# Every runtime S3 call goes through `Brando.CDN.Client`; in test that is a Mox
# mock, so an un-stubbed call fails loudly instead of reaching a bucket.
config :brando, :cdn_client, Brando.CDN.Client.Mock
```

Only `head_object/3` and `delete_object/3` route through `Client.impl()`
(`cdn.ex:397`, `cdn.ex:414`). I grepped `lib/` for every `ExAws.request`/
`ExAws.S3.` call site. Still direct, in **runtime request/job paths**:

| Site | Call | Reachable at runtime? |
|---|---|---|
| `lib/brando/cdn/cdn.ex:308-311` | `Upload.stream_file() \|> S3.upload() \|> ExAws.request(s3_config)` | Yes — `upload_file/3` and `upload_image/4`, both driven by `Worker.FileUploader`/`Worker.ImageUploader` |
| `lib/brando/cdn/cdn.ex:354` | `S3.get_bucket_location() \|> ExAws.request(...)` | Yes — `ensure_bucket_exists/1` |
| `lib/brando/cdn/cdn.ex:362` | `ExAws.S3.put_bucket() \|> ExAws.request()` | Yes, same function. Note this one passes **no config at all** — it silently falls back to `ExAws`'s global app env rather than the resolved `s3_config`, which is a separate latent bug |
| `lib/brando/uploads.ex:472-474` | `ExAws.Config.new(:s3, s3_config)` + `ExAws.S3.presigned_url(...)` | Yes — the presign path. Deliberately excluded per the plan, and correctly so (local HMAC) |
| `lib/mix/tasks/brando.static.deploy.ex`, `brando.files.update_content_disposition.ex` | various | Operator tools — correctly out of scope |

The presign exclusion and the mix tasks are documented and fine. The three
`cdn.ex` bulk/bucket calls are **not** — `client.ex:18-20` says they are excluded
because "a stub proves nothing about them", which is a reasonable design call,
but it directly contradicts the safety property `config/test.exs` asserts. In
test today nothing reaches a bucket only because `Brando.Files`/`Brando.Images`
have `cdn: [enabled: false]` (`config/test.exs:5,12`) — i.e. the guarantee comes
from the CDN being off, not from the Mox seam. If a future test enables a CDN
config to exercise `queue_upload/3` with Oban `testing: :inline`
(`config/test.exs:74`), `s3_upload/7` will attempt a real network call and the
comment will have promised otherwise. `ensure_bucket_exists/1` is worse: it
would try to **create a bucket**.

The seam is fine; the claim written above it is the defect. It is the kind of
comment a future reader will trust instead of grepping.

---

## Warnings

### WARNING 1 — `validate_required(:uid)` has no matching DB constraint in the test fixtures

`lib/brando/content/block.ex:166` and `:208` (correctly applied to **both**
`block_changeset/3` and `recursive_block_changeset/3` — checked, no asymmetry):

```elixir
|> cast(attrs, @block_attrs)
|> validate_required(:uid)
|> unique_constraint(:uid)
```

But the column is nullable:

```
priv/repo/migrations/20160219000000_test_migrations.exs:296
  add :uid, :text          # no null: false
```

Compare `content_refs`, which got it right at line 324: `add :uid, :string, null: false`.
Phase 4 added the *unique* index for uid but not the null constraint, so the
"declared-but-unenforced contract" is only half closed: any write that bypasses
these two changesets (`Repo.insert_all`, `Changeset.change/2`, a factory) can
still land a NULL uid, and Postgres's unique index permits **unlimited NULLs**.
The stated goal ("a uid is the block's identity everywhere it matters") is not
actually enforced by the schema.

**Flow analysis — can `validate_required(:uid)` break a legitimate path?**
I traced the four the brief asked about:

- *Existing blocks with partial params* — safe. `validate_required` reads through
  `get_field/2`, which falls back to `changeset.data`. A reorder/partial save that
  sends only `id` + `sequence` still sees the persisted uid.
- *Deleted / replaced children* — safe. `cast_assoc` does not invoke the `with:`
  function for changesets it marks `:replace`, nor for `drop_param` removals, so
  the validation never runs on them.
- *`finalize_new_block/2`* (`block.ex:183-203`) — runs **after** the validation and
  only does `Map.put(:action, :insert)` plus `update_change` rejections. It does
  not clear errors, so a new block with no uid in params stays invalid and
  `cast_assoc` propagates `valid?: false` to the entry changeset. Verified that
  `duplicate_block/2` always supplies one (`blocks.ex:1053`,
  `uid = Keyword.get(opts, :uid, Utils.generate_uid())`), and refs likewise
  (`blocks.ex:1176`), so the duplication path is covered.
- *New blocks pre-uid-assignment* — this is the residual risk. The uid reaches the
  server as a form param via the hidden input (`block/render.ex:1331` for refs;
  block-level uid rides in the block form). Any client path that creates a block
  and posts before the uid input is rendered now produces a save failure nested
  under `entry_blocks`, which is where changeset errors are least visible in this
  UI. The suite is green, but no test in this diff exercises "block created and
  saved in the same round-trip".

### WARNING 2 — `reject_deleted/2` runs at save, not at validate — the new validation sees deleted blocks

`lib/brando_admin/components/form.ex:5551-5560`:

```elixir
defp assoc_all_block_fields(block_changesets, changeset) do
  Enum.reduce(block_changesets, changeset, fn {field_name, block_cs}, updated_changeset ->
    updated_block_cs =
      block_cs
      |> Brando.Content.Blocks.reject_deleted(true)
      ...
```

This is in the **save** path only. The `validate` handler
(`form.ex:3038`) calls `validate(schema, entry_or_default, entry_params, current_user)`
→ `schema.changeset(params, user)` with the raw params, so blocks the editor has
marked deleted but not yet pruned still go through `block_changeset/3` and now
through `validate_required(:uid)`. If any deleted-but-not-yet-swept block lacks a
uid in its params, the entry form now reports invalid during typing where it
previously did not. Low likelihood (deleted blocks generally have uids), but this
is the interaction the brief asked about and it is not covered by a test.

### WARNING 3 — the unique index has no dedupe step and will fail on any populated database

`priv/repo/migrations/20260806000001_unique_block_uid_in_test_schema.exs:19`

```elixir
create unique_index(:content_blocks, [:uid])
```

Fine on a freshly-created test DB. But `e2e/priv/repo/migrations` is a **symlink**
to `priv/repo/migrations` (per AGENTS.md), so this migration also runs against the
long-lived e2e database, which has been seeded and hand-edited across the whole
block-editor refactor — and until this commit nothing prevented duplicate uids
there. The migration has no `execute` to null-out or re-generate duplicates first,
so on any such DB it fails with `could not create unique index ... Key (uid)=(…)
is duplicated` and leaves the migration table wedged.

Rollback is fine (`create unique_index` auto-reverses to `drop`). It also is not
`concurrently`, which is correct for test but means a consuming app that ever
copies this pattern to production takes a full table lock.

### WARNING 4 — `modify … from:` reversibility depends on constraint names that are never asserted

`priv/repo/migrations/20260806000000_nilify_asset_fks_in_test_schemas.exs:32-44`

```elixir
for {table, column} <- @image_fks do
  alter table(table) do
    modify column, references(:images, on_delete: :nilify_all), from: references(:images)
  end
end
```

Reversibility itself is correct: `from:` is supplied, so `change/0` is reversible
and Ecto reverses commands in reverse order. The `for` comprehension inside
`change/0` works because `alter/2` is a runner side effect, not a return value.

Two real fragilities:

1. Ecto's `modify` with a `references/2` emits `DROP CONSTRAINT <name>` +
   `ADD CONSTRAINT <name>`, deriving `<name>` as `#{table}_#{column}_fkey`. That
   matches the originals (verified: `test_migrations.exs:51,179,393,394,395,450,467`
   all use the unnamed default). But it is an *implicit* dependency — if any of
   these seven ever gains an explicit `name:`, this migration silently fails on a
   `DROP CONSTRAINT` of a nonexistent name.
2. The changed-file list calls this "seven columns", and the moduledoc says
   "Seven columns … declared as a bare `references`". `@image_fks` has 6 entries
   and `@file_fks` has 1 — that is seven. Checked, no issue.
3. `{:projects, :cover_id}` etc. target the **test** `projects` table
   (`test_migrations.exs:393-395`). The e2e blueprint table is
   `projects_projects` (`20250528084400_…:5`) and already declares
   `on_delete: :nilify_all` on its own FKs. Since both migration files live in the
   same (symlinked) directory, both tables exist in both databases, so the
   `alter` finds its target in each. Checked, no issue.

### WARNING 5 — `kill_live/1` permanently flips `:trap_exit` on the test process

`test/support/live_case.ex:101`

```elixir
Process.flag(:trap_exit, true)
Process.exit(pid, :kill)
```

The previous value is never captured or restored. Every linked process that dies
later in that same test now delivers `{:EXIT, …}` to the mailbox instead of taking
the test down — so a genuine crash after a `kill_live/1` call becomes a silent
message the test ignores. `form_recovery_test.exs:51,74,98` all call `kill_live`
mid-test and then continue asserting.

### WARNING 6 — `flush_exits/0` drains the whole mailbox of exits, not just the expected one

`test/support/live_case.ex:114-120`

```elixir
defp flush_exits do
  receive do
    {:EXIT, _pid, _reason} -> flush_exits()
  after
    50 -> :ok
  end
end
```

No pid match. Combined with WARNING 5 this means a crash in an unrelated linked
process during that 50 ms window is swallowed with no trace. A selective receive
on the proxy pid would be exact; this is a shotgun.

---

## Suggestions

### SUGGESTION 1 — `selected_option/2` diverges from browser behaviour for `<select>`

`test/support/live_case.ex:219-227`

```elixir
|> Enum.find(fn {_, attrs, _} -> List.keymember?(attrs, "selected", 0) end)
|> case do
  nil -> []
```

A browser submits the **first** option's value for a single-select with no
explicit `selected`. This returns `[]`, omitting the field entirely. Since the
module's whole thesis is "serialize the DOM and nothing else, because that is
what recovery replays" (moduledoc lines 169-180), a divergence here means a
recovery test can conclude "not recoverable" for a select that production
recovers fine. Also no `multiple` handling, and no `<optgroup>` traversal —
`Floki.find("option")` does descend, so optgroups happen to work.

### SUGGESTION 2 — `Keyword.merge` lets config clobber the request being built

`lib/brando/videos/uploaders/bunny.ex:433` and `lib/brando/videos/uploaders/mux.ex:575`

```elixir
request_opts = Keyword.merge(request_opts, req_options())
```

Config wins on collision, so a `:req_options` containing `:url`, `:method`,
`:headers` or `:json` silently overrides the values the function just computed —
including the auth header. That is exactly the seam's purpose for `plug:`, but the
merge direction is unrestricted. Restricting the seam to a known key
(`Keyword.put_new`-style for everything except `:plug`/`:retry`/`:receive_timeout`)
would keep the test capability while making the required parts non-overridable.

The `get_config/1` shape is consistent between the two and correct:

```elixir
:brando |> Application.get_env(__MODULE__, []) |> Keyword.get(key)
```

`req_options/0` (`bunny.ex:449`, `mux.ex:591`) with `|| []` handles both "key
absent" and "key set to nil". Checked, no issue. Note the test at
`provider_client_test.exs:30-45` documents the one real hazard here (storing `nil`
as the module config makes `Keyword.get/2` raise) and handles it with
`Application.delete_env/2` — good.

### SUGGESTION 3 — `upload-manager-queue-form` id: no collision in this repo, but nothing enforces it

`lib/brando_admin/live/upload_manager.ex:651`

```elixir
<form id="upload-manager-queue-form" phx-change="validate_queue" class="upload-manager-queue-form">
```

Grepped the whole repo: `upload-manager-queue-form` appears exactly once, and
`brando-upload-manager` (line 643) likewise. The manager is rendered as a single
sticky `live_render`, so no in-repo duplication. Two notes:

- Both ids are **unprefixed globals** in a library that consuming apps embed. A
  consuming app cannot know these are taken. The surrounding container already
  uses a `brando-` prefix (`brando-upload-manager`); the new form id does not
  follow it.
- The recovery consequence is benign: `handle_event("validate_queue", _params, socket)`
  (`upload_manager.ex:75`) ignores params entirely and only sweeps
  `socket.assigns.uploads.queue.errors`, so the extra event LiveView now pushes on
  reconnect is a no-op. Checked, no issue.
- Nothing else keys off the old markup — the hook is on the outer div
  (`phx-hook="Brando.UploadManager"`, line 644), not the form, and the JS finds
  the file input via `live_file_input`'s own ref. Checked, no issue.

### SUGGESTION 4 — the `[_]` → `_` widening in `form.ex` is right, but the fallback skips live-preview invalidation

`lib/brando_admin/components/form.ex:3095-3096`

```elixir
_ ->
  {:noreply, maybe_finish_live_preview_recovery(socket)}
```

The clause is reachable (proved by `form_recovery_test.exs:96`,
`assert captured["_target"] == ["image_editor_upload"]`) and it does fix the
`CaseClauseError`. But unlike the `[^singular | rest]` branch it does not call
`maybe_invalidate_live_preview_assign/3` or `maybe_fetch_root_blocks/3`. On the
recovery push — which now restores the entry's values — the live preview is only
refreshed if `live_preview_recovery_pending?` happens to be true
(`form.ex:4445-4451`). If a preview is open but that flag was already consumed,
the recovered values are in the form and stale in the preview. Not a regression
(the old code did nothing at all here), but the fix restores the form without
restoring what renders from it.

### SUGGESTION 5 — `provider_client_test.exs:23-24` double-uses ExUnit.Case

```elixir
use ExUnit.Case, async: false
use Brando.ConnCase
```

`Brando.ConnCase` is an `ExUnit.CaseTemplate` and already brings the case in. The
explicit `use ExUnit.Case` is redundant; if `ConnCase` ever sets `async: true` by
default the two would silently disagree. Prefer `use Brando.ConnCase, async: false`.

---

## Pre-existing (one line each, not analysed)

- `lib/brando_admin/components/form.ex:3047` — `entry.id` in the dirty-fields
  broadcast will raise when `entry` is nil, which line 3036 (`entry || struct(schema)`)
  proves is an expected state.
- `lib/brando_admin/components/form.ex:3038` — `validate/4` passes `Map.get(params, singular)`
  straight to `cast/3`; a `validate` with no singular key raises `ArgumentError` on nil params.
- `lib/brando/uploads.ex:229-232` — `rescue exception ->` wrapping a whole `with` as
  control flow (Iron Law #5); catches far more than the `get_s3_config/2` raise the
  comment names.
- `lib/brando/cdn/cdn.ex:362` — `ExAws.request()` with no config, inside a function
  that resolved `s3_config_list` two lines earlier.
- `lib/brando/videos/uploaders/bunny.ex:401`, `mux.ex:543` — `unless`, deprecated in
  Elixir 1.18+.
