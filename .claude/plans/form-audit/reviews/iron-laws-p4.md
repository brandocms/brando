# Iron Law Violations Report — Phase 4 (HEAD~5..HEAD)

## Summary
- Files scanned: 12 source files in scope (tests/e2e read for context only)
- Iron Laws checked: 26 of 26 (pattern sweep), deep-read on `form.ex`, `upload_manager.ex`, `cdn.ex`, `client.ex`, `bunny.ex`, `mux.ex`, both migrations, `live_case.ex`
- Violations found: 5 (0 blocker, 3 warning, 2 suggestion)

Not violations (checked, clean): no `:float` money fields; no unpinned/interpolated
query values (`fragment("? @> ?", j.args, ^args)` is pinned); no `raw/1` on
untrusted content in changed code; no Oban atom-key args or structs in args; no
`{:snooze, _}` + `attempt` guard; no `Mix.Task.run("app.start")`; no
`Application.compile_env` where runtime is needed — `Brando.CDN.Client.impl/0`,
`Bunny.get_config/1` and `Mux.get_config/1` all use `Application.get_env/3` per
call, which is correct and is what makes the new seams swappable in tests. Both
new migrations use `change/0` with reversible operations (`modify … from:`,
`create unique_index`) — auto-reversible, no `down` needed.

---

## High Violations (WARNING)

### [Raising vs returning] `String.to_integer/1` on client-supplied recovery params
- **File**: `lib/brando_admin/components/form.ex:6287`, `:6315`, `:6343`
- **Code**: `resource_id = String.to_integer(params["resource_id"])`
- **Confidence**: LIKELY
- **Why**: `params` here come from `handle_event("recover_drawer_state", …)` — i.e.
  hidden inputs replayed from the DOM on reconnect, which is client-controlled
  input under the security Iron Law "LiveView event params are untrusted". The
  only guard is `when id != ""` (form.ex:6152/6155/6158); any non-numeric value
  (`"abc"`, `"1x"`, `"9999999999999999999999"` is fine, but `"1.0"` is not)
  raises `ArgumentError`. That raise happens *during recovery*, so the freshly
  reconnected LiveView dies immediately and the user gets a reconnect loop —
  precisely the failure mode this phase's harness was built to catch.
- **Fix**: `Integer.parse/1` + fall through to the existing `{:noreply, socket}`
  no-op branch, e.g.
  `with {id, ""} <- Integer.parse(params["resource_id"]), {:ok, image} <- Brando.Images.get_image(id) do … else _ -> {:noreply, socket} end`.

### [Raising vs returning] `String.to_existing_atom/1` on client-supplied recovery params
- **File**: `lib/brando_admin/components/form.ex:6294`, `:6296`, `:6322`, `:6324`, `:6350`, `:6352`, `:6459`
- **Code**: `field: String.to_existing_atom(params["field"]),`
  `schema: String.to_existing_atom(params["schema"]),`
  and `{:ok, list} when is_list(list) -> Enum.map(list, &String.to_existing_atom/1)`
- **Confidence**: LIKELY
- **Why**: `to_existing_atom` correctly closes the atom-exhaustion hole (Iron Law
  #10 is satisfied — this is *not* a `String.to_atom` finding). The remaining
  problem is the *raise*: it throws `ArgumentError` for any unknown string and
  `FunctionClauseError` for `nil` or a non-binary. `params["field"]` and
  `params["schema"]` have no guard at all at the call site, and
  `decode_recovery_path/1` (6457-6462) maps over a JSON-decoded list whose
  elements are only checked to be a *list*, not binaries — `[1,2]` decodes fine
  and then crashes in `String.to_existing_atom/1`. Same reconnect-loop blast
  radius as above.
- **Fix**: wrap in a helper returning `{:ok, atom} | :error`
  (`try/rescue ArgumentError` at the boundary, or a whitelist check against
  `socket.assigns.schema.__asset_fields__()` / the known drawer fields), and for
  `decode_recovery_path/1` narrow the guard to
  `{:ok, list} when is_list(list) -> Enum.flat_map(list, &safe_atom/1)`.

### [#5-adjacent / rescue-as-control-flow] Bare `rescue` catching every exception in the sticky UploadManager
- **File**: `lib/brando_admin/live/upload_manager.ex:492-505`
- **Code**:
  ```elixir
  rescue
    exception ->
      Logger.error("==> UploadManager: finalize raised for #{inspect(item.direct.key)}: " <> …)
      {:error, Exception.message(exception)}
  ```
- **Confidence**: REVIEW
- **Why**: Elixir Iron Law "rescue only for external code, never for control
  flow". The comment is honest about the cause — `Brando.CDN.get_s3_config/2`
  (`lib/brando/cdn/cdn.ex:88-124`) raises outright when a target's CDN config is
  missing, and `cdn_config.bucket` in `head_object/2` (cdn.ex:394-397) /
  `delete_object/2` (cdn.ex:411-414) raises `BadMapError`/`KeyError` when
  `Map.get(field_cfg, :cdn)` returns `nil`. The mitigation (protect the sticky
  process so one bad target does not kill every in-flight upload) is legitimate,
  and this is the *right* place for a defensive boundary — but a catch-all here
  also swallows genuine bugs (a `MatchError` in `finalize_direct/3`, an
  `Ecto.NoResultsError`) as an ordinary per-item error, indistinguishable in the
  UI from "your file failed to upload".
- **Fix**: keep the boundary, but make the config path return rather than raise —
  a `Brando.CDN.fetch_s3_config/2` returning `{:ok, cfg} | {:error, :no_cdn_config}`
  that `finalize_direct/3` threads through the existing `with`. If the rescue
  stays as a backstop, narrow it to the exception types that can actually reach it
  (`rescue e in [KeyError, BadMapError, RuntimeError]`) so an unexpected crash
  still crashes.

---

## Medium Violations (SUGGESTION)

### [#11] Recovery handler loads a client-named resource without re-authorizing
- **File**: `lib/brando_admin/components/form.ex:6286-6368`
- **Code**: `case Brando.Images.get_image(resource_id) do` (and the video/file twins)
- **Confidence**: REVIEW
- **Why**: `resource_id`, `field`, `schema` and the replayed `changes` JSON all
  arrive from the reconnecting client. The handler loads the resource and opens
  an edit drawer over it with no `socket.assigns.current_user` check. Mitigating:
  the whole admin surface is behind `{BrandoAdmin.UserAuth, :ensure_authenticated}`
  and Brando's asset library has no per-user scoping, so the practical exposure is
  one authenticated admin opening another's asset — which they can already do
  through the picker. Recording it because Iron Law #11 wants the check at the
  event, not only at mount, and because `replay_drawer_changes/3` then `cast/3`s
  client JSON onto that resource (it is correctly limited to
  `@image_drawer_fields`/`@video_drawer_fields`/`@file_drawer_fields`, which is
  what keeps this a suggestion rather than a warning).
- **Fix**: if/when assets gain ownership scoping, thread `socket.assigns.current_user`
  into the three `restore_*_drawer/2` lookups.

### [#19] Change-narration comments in new code
- **File**: `lib/brando/cdn/client.ex:9`, `lib/brando_admin/live/upload_manager.ex:416-418`, `lib/brando/videos/uploaders/mux.ex:572-574`, `lib/brando/videos/uploaders/bunny.ex:430-432`
- **Code**: e.g. `client.ex:9` — *"which is recorded as the honest limit of the D1 work in the form audit's Phase 2"*; `upload_manager.ex:416` — *"Deliver BEFORE queueing processing — with Oban testing: :inline …"*
- **Confidence**: REVIEW
- **Why**: Iron Law #19 — reasoning about *why this change was made* and
  references to plan phases ("the form audit's Phase 2", "Phase 4") are commit/PR
  content, not code content; a reader six months out has no way to resolve them.
- **Keep, do not flag**: the surrounding text in the same blocks is durable
  intrinsic fact and should stay — that `presigned_url/5` is local HMAC not a
  network call (`client.ex:14-17`), the ordering constraint in
  `upload_manager.ex:416-418`, the `req_options` transport seam note, the
  `live_case.ex` "these tests must not be `async: true`" invariant, and both
  migration moduledocs (which document a real production/fixture divergence).
  Only the plan-phase back-references are worth trimming.

---

## Pre-existing (one line each, not in scope)
- `lib/brando/cdn/cdn.ex:424` — bare `rescue _ -> false` in `enabled?/1` hides config errors as `false`.
- `lib/brando/cdn/cdn.ex:76,92,265` — `raise` on missing S3 config; the raising path the new rescue in `upload_manager.ex` exists to absorb.
- `lib/brando/cdn/cdn.ex:221,293` — `File.rm!/1` after a successful upload will crash the Oban worker if the local file is already gone.
- `lib/brando_admin/components/form.ex:3552` — `{:ok, img} = Brando.Repo.update(changeset)` crashes the LiveView on a changeset error instead of rendering it.
- `lib/brando_admin/components/form.ex:3901` — `{:ok, new_image} = Brando.Repo.insert(validated_changeset)`, same.
- `lib/brando/videos/uploaders/mux.ex:543` / `bunny.ex:401` — `unless api_key do raise …` inside `api_request/3`; raises from a webhook/LiveView path rather than returning `{:error, :not_configured}`.
