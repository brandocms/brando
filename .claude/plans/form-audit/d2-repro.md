# D2 repro — is the delivery topic stranded by a form remount?

**Status:** waiting on an empirical result.

> **Correction (2026-08-05): the first version of this doc used
> `liveSocket.disconnect()`. That is the wrong trigger.** The UploadManager is
> rendered `sticky: true` (`lib/brando_admin/components/layouts/live.html.heex:3`),
> so it survives *live navigation* but **not** a socket drop — a drop tears down
> the whole LiveView tree, sticky children included. So a disconnect kills the
> upload itself and lands in D1's territory (already fixed), instead of testing
> D2's premise: manager alive, form replaced.
>
> **Live navigation is the trigger** — and it is also the realistic user story:
> start a big upload, click to another entry, come back.

## What already shipped

Only the instrumentation, plus one correction to the finding: the failure was
previously **completely silent**, not a `:debug` line (that line only fires for
an item carrying *no* `deliver_topic`; a broadcast to a live-but-unlistened
topic returns `:ok` and logs nothing).

- `upload_manager.ex` `deliver/2` → `delivering asset #<id> to <topic>`
- `form.ex` `mount/1` → `listening for asset delivery on <topic>`

## Setup

```bash
cd e2e && source .envrc
MIX_ENV=e2e mix ecto.migrate          # already applied 2026-08-05
MIX_ENV=e2e PORT=4444 iex -S mix phx.server
```

**Reading the listening topic needs no logs at all** — the form already renders
it (`form.ex:1897`, `data-deliver-topic`, there for the upload hooks). In the
browser console:

```js
document.querySelector('[data-deliver-topic]').dataset.deliverTopic
```

That is all Part A needs.

The *delivery* side (Part B) is a server log, and the e2e logger sits at
`:warning` while both new lines are `Logger.info`. Don't edit config — you are
already at an `iex` prompt, so just:

```elixir
Logger.configure(level: :info)
```

Instant, no restart, nothing to revert. (`e2e/config/e2e.exs:5` is the
persistent version if you prefer, but it needs a restart.)

Use `MIX_ENV=e2e`, not `test` — see the note at the bottom. Log in at
http://localhost:4444 with `admin@brandocms.com` / `brandocms`. If the user
doesn't exist, seed: `BRANDO_SEEDING=true MIX_ENV=e2e mix run priv/repo/e2e_seeds.exs`

---

## Part A — no upload, no race, ~20 seconds

> **This section had two jobs and the wording confused them. Read the pass
> condition carefully.**
>
> - *Before* the fix it demonstrated the bug: any two mounts gave different topics.
> - *After* the fix it verifies it: the same entry must give the same topic,
>   while two different entries must still give different ones.
>
> Two different projects showing different topics is **correct**, not a failure.

Read the topic with:

```js
document.querySelector('[data-deliver-topic]').dataset.deliverTopic
```

1. Open project **1** → topic `<A>`
2. Open project **2** → topic `<B>`
3. Go **back to project 1** → topic `<C>`

**Pass:** `<C>` == `<A>`, and `<B>` != `<A>`.
**Fail:** `<C>` != `<A>`.

Verified 2026-08-05 via devtools: `<A>`=`form:a50aa0e4…`, `<B>`=`form:3c0b7a58…`,
`<C>`=`form:a50aa0e4…`. Typing into a field afterwards (forcing a server
re-render) left the attribute unchanged, which is what proves the **server**
adopted the client's topic rather than re-patching its own over it.

Before the fix, step 3 always produced a third new topic — the whole bug, since
`put_intake_item/6` captures `deliver_topic` at intake and never updates it.

## Part B — the user-visible loss

Only needed to see what actually happens to the asset. This is where the
timing matters, so widen the window rather than fighting it:

- **Throttle**: devtools → Network → Slow 4G (or custom ~1 Mbps). The bytes ride
  the LiveView websocket, so throttling slows the upload directly.
- **Use a big file**: none of the e2e project's assets set a `size_limit`, so
  the 50 MB global default applies (`Brando.Uploads @max_file_size`). A ~40 MB
  image is fine. `cover_video` and `cover_file` (PDF only) have the same
  ceiling if you'd rather test those.

Then:

1. Start the upload on `listing_image`.
2. **While the drawer shows it transferring**, click through to another project
   in the admin — ordinary navigation, no console commands.
3. Watch the manager drawer: the upload should keep going (it is sticky).
4. When it finishes, read `UploadManager: delivering asset #N to form:<A>` and
   compare with the `form:<B>` the current form is listening on.
5. Go back to the original project. Is the image on the field, or only in the
   library?

## What to report

- Part A's `<A>` and `<B>`
- Part B's delivery topic vs the then-current listening topic
- whether the image ended up on the field or only in the library
- **did the upload survive the navigation at all?** If the sticky manager keeps
  transferring, a stable topic is most of the fix. If it dies too, that is a
  different (larger) bug and the ACK design changes accordingly.

## Then

- Stranded as predicted → derive `deliver_topic` from entry identity instead of
  a per-mount UUID. The mount comment gives two reasons for the UUID — create
  forms have no id yet, and two tabs on one entry must not share a topic — so
  something like `"form:<schema>:<entry_id or new>:<per-tab uuid>"`, where the
  uuid is stable per browser tab rather than per mount.
- The ACK + bounded retry is the second half, and whether it earns its
  complexity depends on the last question above.

---

> **`MIX_ENV=e2e`, not `test`.** `test_e2e.sh` and AGENTS.md use `e2e`; only
> `run_e2e.sh` uses `test`, whose `_build` drifts out of sync with `mix.lock`
> (it held decimal 2.4.1 / ecto_sql 3.13.5 against a lock of 3.1.1 / 3.14.0 and
> failed the dep check outright — looking exactly like broken deps when nothing
> was wrong with them). If it happens again:
> `MIX_ENV=<env> mix deps.compile decimal ecto_sql ecto --force`. Both envs were
> resynced 2026-08-05.
