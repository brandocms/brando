# Phase 9E — Close the Phase 9 review

**Source:** `.claude/plans/form-audit/reviews/phase-9-review.md` (1 BLOCKER, 2 WARNINGs, 5 SUGGESTIONs)
**Slug:** `form-audit` · **Depth:** standard · **Created:** 2026-08-07

Own file, following the Phase 5–9 precedent. No research agents: the review is
the research.

---

## The blocker's fix is not the one the review proposed

The review recommended hoisting `form.ex`'s `rescue` into
`Brando.Videos.Uploader`. **Rejected during planning, and the reason is worth
keeping.**

9B converted Cloudflare's `{:error, :not_configured}` into a raise. A rescue in
the facade converts it straight back into a tuple. The net contract at the call
site would be identical to pre-9B Cloudflare, plus a `rescue` — 9B's breaking
change would have bought nothing, and the audit would be carrying a decision
whose effect it had quietly undone one layer up.

The real defect is that **9B's mechanism does not match its own rationale.** The
rationale is *"missing credentials are a deploy-time config error, not a runtime
condition"* (`cloudflare.ex:272-277`). But the check lives in `api_request/4` —
the hot path — so it fires at file-pick time, which is the latest and worst
possible moment, with the user's unsaved work in the blast radius. That is not
fail-fast; it is fail-late dressed as fail-fast.

**So: check credentials where the other pre-flight conditions are already
checked.** `Brando.Uploads.validate_provider_video_intake/2` (`uploads.ex:489`)
is a `with` chain of `:ok <-` validators that `Uploader.initiate_upload/3`
already threads (`uploader.ex:149`). A missing credential belongs in it,
alongside `validate_upload_enabled/1` and `validate_provider_strategy/1`.

What this buys, versus the rescue:

| | Rescue in facade | Validation in the existing chain |
|---|---|---|
| 9B's raises | caught, contract undone | **untouched, still raise** |
| Mechanism | catch your own exception | pre-flight validation, like its neighbours |
| Call-site changes | none | none — both already have `{:error, reason}` branches |
| Public contract | `initiate_upload/3` changes *again* | unchanged |
| Provider raise becomes | dead code the facade eats | genuine last-resort invariant guard |

The raises stay exactly as Phase 9B decided. They simply stop being reachable
through the admin path, which is what "deploy-time config error" was always
supposed to mean.

---

## Tasks

### 9E-1 — Give each provider a credential predicate `[elixir]`

The three `api_request` heads each inline their own credential check. Extract
the predicate so the validator and the raise cannot drift apart.

- [x] `lib/brando/videos/uploaders/cloudflare.ex` — add `configured?/0`, and
      make `api_request/4` (`:268`) branch on it rather than re-testing inline
      — `unless configured?()`, credentials read *after* the guard
- [x] `lib/brando/videos/uploaders/mux.ex` — same, against `api_request/3` (`:539`)
- [x] `lib/brando/videos/uploaders/bunny.ex` — same, against `api_request/3` (`:398`)
      — only `:api_key` is a credential; `library_id`/`cdn_hostname` are routing
      values and `api_request/3` never checked them, so `configured?/0` doesn't either

```elixir
# cloudflare.ex — the predicate the raise already uses, named and made public
@doc false
def configured?, do: present?(get_config(:account_id)) and present?(get_config(:api_token))

defp api_request(method, path, body \\ nil, extra_headers \\ []) do
  unless configured?() do
    raise """
    Cloudflare credentials not configured. Please add to your config:
    ...
    """
  end
  ...
end
```

**Resolve the `present?/1` asymmetry while here.** `cloudflare.ex:279-282`
records that Cloudflare uses `present?/1` while Mux and Bunny use truthiness, so
an empty-string credential is caught by one and not the other — deliberately
left alone in 9B because it was about *detecting* the failure, not reporting it.
9E is about detection, so it is now in scope. Use `present?/1` in all three.

- [x] Move `present?/1` somewhere the three can share it, or duplicate it
      consistently — either is fine, but all three must agree — **duplicated
      consistently**, matching how `get_config/1` is already triplicated. The
      three symmetric `configured?/0` tests are the anti-drift mechanism
- [x] Delete the now-stale second paragraph of the `cloudflare.ex:279-282`
      comment once the asymmetry is gone — whole block replaced, see 9E-6

**RED first:** a test asserting `Mux.configured?() == false` with
`access_token_id: ""` must fail before the change and pass after.

**RED measured, and the defect is worse than the plan described.** Written
behaviourally (`Mux.initiate_upload` with `access_token_id: ""` must raise) so
it could fail pre-change for the *right* reason rather than merely because
`configured?/0` did not exist. Pre-change it did not raise — and `with_config/2`
installs no transport stub, so the empty-credential test **made a real network
request to the live Mux and Bunny APIs**, carrying an empty auth header. That is
what truthiness bought: not a bad error message, an unauthenticated outbound
request. Post-change: 19/19, and the file's runtime drops 0.9s → 0.2s because
those two cases no longer reach the network.

Mutation run in both directions: Mux's predicate → truthiness reddens exactly
`"Mux rejects an empty-string credential"` + the shared empty-value test, with
Bunny and Cloudflare green. Restored, 19/19.

### 9E-2 — Validate credentials in the existing pre-flight chain `[elixir]` `[BLOCKER]`

- [x] `lib/brando/uploads.ex:489` — add `validate_provider_credentials/1` to the
      `with` chain in `validate_provider_video_intake/2` — three explicit
      strategy clauses + an `{:error, {:unknown_strategy, …}}` catch-all, per
      the risk note. **Blocker closed.**

```elixir
def validate_provider_video_intake(cfg, %{name: name, size: size} = file_meta) do
  with :ok <- validate_upload_enabled(cfg),
       :ok <- validate_provider_strategy(cfg),
       :ok <- validate_provider_credentials(cfg),
       :ok <- validate_intake(:video, name, size, size_limit(cfg)),
       :ok <- validate_optional_mimetype(cfg, Map.get(file_meta, :type), name) do
    :ok
  end
end

defp validate_provider_credentials(%{upload_strategy: :mux}),
  do: if(Brando.Videos.Uploaders.Mux.configured?(), do: :ok, else: {:error, :provider_not_configured})

# ...bunny, cloudflare; strategies without provider credentials return :ok
defp validate_provider_credentials(_), do: :ok
```

Order matters: **after** `validate_provider_strategy/1` (so a non-provider
strategy is rejected on its own terms first) and **before**
`validate_intake/4` (no point size-checking an upload that cannot start).

**This is the task that closes the blocker.** Both unrescued call sites —
`video_picker.ex:463` and `transformer.ex:909` — already have `{:error, reason}`
branches, so they need no edit; they simply stop receiving an exception.

**RED measured against a mounted LiveView, per the plan's own instruction not to
settle for a re-read.** `test/brando_admin/live/video_picker_credentials_test.exs`
mounts the real page form, picks a video, and asserts `Process.alive?/1`.
Dropping the validator from the `with` chain reddens it with the blocker's
stacktrace verbatim: `VideoPicker.handle_event/3 (video_picker.ex:463)` →
`Cloudflare.initiate_upload/3` → `api_request/4` → `RuntimeError` → dead view.

**Two things the review did not have, both found by making the test reach the
call site.** Neither changes the fix; both change what the fix is *for*.

1. **The exposure is narrower than the review stated, and not for a reassuring
   reason.** All three upload surfaces gate their trigger on
   `Brando.Uploads.video_upload_available?/1`, so a wholly credential-less
   deploy renders no button. But that gate is computed in `update/2` and never
   re-checked in `handle_event/3`, while providers read config at *call* time —
   so it is a render-time snapshot, not a guard. A credential rotated or
   mis-deployed after the last update leaves a live trigger on the page. The
   test models exactly that, which is the plan's own "config is read at call
   time" risk showing up as a live defect rather than a note.
2. **`video_upload_available?/1` is a fourth credential check with a fourth set
   of rules** — it additionally demands `webhook_secret`, and its `present?/1`
   accepts any non-nil non-empty term where the providers' accepts only a
   non-empty binary. So a non-binary `account_id` renders the button and fails
   the provider check. 9E-1 unified three of the four; this is the one left.

**Routing the test event was itself a trap worth recording.** The browser pushes
via `pushEventTo(this.el.dataset.target, …)`, and LiveViewTest reads only
`phx-target`. Both obvious harness spellings — `element(…) |> render_hook(…)` and
`with_target("#video-picker")` — fall through to the *root* LiveView, where
`hooks.ex:895` forwards to `Form`, the one call site that was already rescued.
The test passed that way, against the unfixed code. It now reads the CID out of
`data-target` and hands it to `with_target/2`, which is what the hook does.
*A test that cannot reach the defect is green for the same reason the defect is
invisible.*

### 9E-3 — Map the error to a fixed user-facing string `[liveview]`

Closes SUGGESTION 1 and a second instance of it the review panel missed.

- [x] `form.ex` — add an `extract_video_error_message/1` clause for the atom,
      above the `is_binary/1` clause at `:5741` — delegates to the shared owner

```elixir
defp extract_video_error_message(:provider_not_configured),
  do: "Video provider is not configured. Check server configuration."
```

- [x] `video_picker.ex:~484` — replace `error: inspect(reason)` with the shared
      helper. **The review did not catch this one:** the picker pushes
      `inspect/1` of the raw term to the browser, which is the same channel as
      SUGGESTION 1 and strictly worse than `form.ex`'s string
- [x] `transformer.ex` — confirm `upload_error_message/1` has a clause for the
      new atom and does not fall through to an `inspect/1` default — it did
      fall through (`to_string/1` for atoms), so it now delegates too

**One owner, not three clauses.** `Brando.Uploads.video_upload_error_message/1`
holds the text, because three surfaces report the same failures on the same
browser channel and they had already drifted. Its atom clauses come first: those
are the errors this module *produces*, so they are the ones an operator can act
on, and an `inspect/1`/`to_string/1` fallback is exactly how `:provider_not_configured`
reaches an editor. `transformer.ex`'s four private clauses became its tail.

### 9E-4 — Decide the fate of `form.ex`'s rescue `[elixir]`

`form.ex:5816-5834`. With 9E-2 in place it no longer catches the credentials
case. It still catches *unexpected* provider exceptions (Req failures, JSON
decode, a provider lib bug) — which is a legitimate backstop, and materially
different from using a rescue to handle an expected, decided-upon condition.

But it exists at one of three call sites, so the non-credential exposure the
blocker described persists in narrower form at the other two.

- [x] **Decide:** keep it local to `form.ex`, or move it to
      `Uploader.initiate_upload/3` as a genuine unexpected-exception backstop
      covering all three — **user chose: move to the facade**
- [x] Return `{:error, :provider_error}` rather than
      `{:error, Exception.message(exception)}` — and the matching
      `extract_video_error_message/1` clause is 9E-3's shared owner. A
      provider's exception text is not written for an editor and can carry
      request detail; a test pins that it does not reach the caller
- [x] Update the comment at `:5811-5815` — `form.ex` now carries a comment
      saying why there is *no* rescue there, so its absence reads as the
      decision it is rather than as an omission

**Recommendation:** move it to the facade. Post-9E-2 it is unambiguously a
backstop for the unexpected, which is the normal, non-messy use of `rescue`, and
one copy beats three.

**Shipped:** rescue on a new `dispatch_initiate_upload/4` (the `with` chain's
validators must stay outside it, or a pre-flight bug would be swallowed as a
provider error). `initiate_upload/3`'s `@doc` now states totality as a contract,
including what the rescue deliberately does *not* catch.

**RED:** `provider_client_test.exs` drives a `Req.Test` stub that raises.
Deleting the rescue reddens exactly the two rescue tests with the raised
`RuntimeError`, while the pre-flight test stays green — which is the point of
testing the two mechanisms apart.

### 9E-5 — Drop the reintroduced fixed wait `[WARNING 1]`

- [x] `e2e/e2e/playwright/tests/blocks/block-recovery.spec.js:235` — replace
      `page.waitForTimeout(750)` with a condition wait on `data-entry-id`
      becoming numeric — folded into a `saveAndContinue/1` helper, since 9E-8
      needs the same wait twice and a duplicated sleep is how the first one
      came back

```js
await expect(hook).toHaveAttribute('data-entry-id', /^\d+$/)
```

`aeb0bce45` removed these from the block specs deliberately. This one sleeps
immediately before reading the very attribute whose transition the test exists
to observe.

### 9E-6 — Make the Cloudflare comment state an invariant `[WARNING 2]`

- [x] `lib/brando/videos/uploaders/cloudflare.ex:272-282` — replace the
      commit narrative with the contract — and the same treatment applied to
      the two comments 9E-1 had just written for Mux and Bunny, which had
      picked up "until 9E" phase labels. A phase number means nothing outside
      this audit; the invariant now names
      `validate_provider_video_intake/2` and says what it means if the raise
      ever fires from a LiveView

The current block explains what the function used to return, when it changed,
and how many times the audit recorded it — all of which the CHANGELOG already
carries, and all of which goes stale on the next change. State the invariant:
missing credentials are a config error and raise. History belongs in the
CHANGELOG. (9E-1 already deletes its second paragraph; this finishes the first.)

### 9E-7 — `Form.VideoDrawer` polish `[SUGGESTIONS 2, 3]`

- [x] `video_drawer.ex` — add the `# prop` doc-comment convention used by
      `meta_drawer.ex` and `scheduled_publishing_drawer.ex` — six props, plus a
      note that `myself` is the *parent's* CID (this is a function component
      and has none of its own), since that is the non-obvious one
- [x] `form.ex:2069` — drop the unused `processing` assign from the
      `VideoDrawer.render` call site, or consume it in the component —
      **dropped**; `grep` confirms the component never referenced it

### 9E-8 — Broaden the C4 e2e coverage `[SUGGESTION 4]` — *optional*

- [x] Extend `block-recovery.spec.js:215` to two distinct entries, so a leak is
      observable as *entry A's value appearing in entry B* rather than inferred
      from a key prefix — **user chose to do it rather than defer**

Shipped as a separate test, `"one entry never recovers another entry's blocks"`,
rather than by widening the existing one — the key-prefix assertion is still
worth having on its own. A is deliberately **not** reconnected before navigating
to B: a successful recovery removes the snapshot, so reconnecting would clear
the very thing that has to still be present when B mounts. It also asserts A's
snapshot is *still there* afterwards, so that a leak which cleaned up after
itself could not pass as correct behaviour.

The existing test is sound and pins the only real `push_patch` path. This is
about matching the finding's framing (C4 is *cross-entry*), not about a gap in
the mechanism. **Defer if Phase 10 is starting** — say so explicitly rather
than leaving the box unticked, per 9A's lesson.

### 9E-9 — Record the mutual compile-time dependency `[SUGGESTION 5]` — *not work*

- [x] Add a note to `plan.md` § G: `VideoDrawer` calls `Form.input/1` and `Form`
      calls `VideoDrawer.render/1`, so the markup move did not decouple from the
      large module — **measured rather than asserted, and it is worse than the
      finding said**: `mix xref` puts `video_drawer.ex` inside a **202-node
      compile cycle**, so it recompiles on the same triggers `form.ex` does.
      Repo-wide: 1 cycle, 919 compile edges. 9C bought line count in one file,
      not coupling and not build time

**This is a finding to carry into Phase 10, not a task.** It changes how
`Chrome` and the `ImageDrawer`/`FileDrawer` pair should be estimated — a markup
extraction that leaves a mutual dependency does not reduce coupling, only line
count. Recording it as a note rather than a checkbox is deliberate: 9A's whole
lesson was that a checkbox nobody will ever tick is worse than a sentence.

---

## Verification

Run after 9E-2, and again at the end:

- [x] `mix compile --warnings-as-errors --force` — clean (603 files)
- [x] `mix format --check-formatted` — clean
- [x] `mix credo --strict` — **baseline 284 (2 / 118 / 152 / 12)**, exact —
      **284 exact**, same split
- [x] `mix test` — **baseline 1291 + 135 doctests / 0 failures** —
      **1305 + 135 / 0**, +14 new
- [x] E2E, user-run: `cd e2e && source .envrc && ./test_e2e.sh --reset` —
      **baseline 108 / 0**. 9E-5 touches a spec, so this is required, not
      optional. **9E-8 adds one**, so the expected count is **109 / 0**.
      No JS or CSS changed, so no consumer asset rebuild is needed —
      both edits are to `block-recovery.spec.js` itself
      — **measured 109 / 0, 9.4m**, the predicted count exactly. The two
      touched specs: `:249` the key-follows-entry test (2.4s, no longer
      sleeping 750ms before reading the attribute it observes) and `:289`
      the new cross-entry test (4.1s)

Unit-suite output measured **25 lines / 13 non-dot / 0 stderr** (warm). The
stderr figure matches the recorded baseline exactly; the other two are *lower*
than the recorded 43 / 27, and I could not reproduce the method behind those
numbers. Recorded as "not a regression" rather than as an improvement — Phase 8
already had one false regression report on this metric that turned out to be a
counting difference, and claiming a win on the same footing would be the same
mistake facing the other way.

**REDs this phase owes, each run in both directions before being believed:**

| Task | RED |
|---|---|
| 9E-1 | `configured?/0` false on empty-string credential — fails pre-change for Mux and Bunny |
| 9E-2 | provider-strategy pick with credentials unset returns `{:error, :provider_not_configured}` and **does not raise** — must raise pre-change |
| 9E-2 | the blocker itself: a `video_picker` pick on a credential-less `:cloudflare` config leaves the LiveView **alive**. Pre-change it dies |
| 9E-5 | spec still passes with the fixed wait removed, and reddens if `data-entry-id` never becomes numeric |

The audit's carried lesson applies to 9E-2's third RED in particular: *"a claim
whose only check is a re-read is not checked."* Kill the LiveView and assert it
survives — do not read the `with` chain and conclude it must.

---

## Risks

**The credential predicate and the raise drift apart.** 9E-1 exists to stop
this, but only if `api_request` genuinely branches on `configured?/0` rather
than keeping its own copy. If a reviewer sees the predicate duplicated inside
`api_request`, 9E-1 failed.

**`validate_provider_credentials/1`'s catch-all `:ok` hides a fourth provider.**
A provider added later without a clause silently validates. Consider matching on
the known strategies explicitly and letting an unknown one fail loudly — the
`{:error, {:unknown_strategy, strategy}}` branch at `uploader.ex:162` already
sets that precedent.

~~**Config is read at call time, not boot.**~~ **CLOSED 2026-08-07**, after
Phase 10, by `Brando.Videos.ProviderConfigCheck` running from
`Brando.Supervisor.init/1`. It logs rather than raising — refusing to boot would
turn a misconfiguration into an outage and break every environment that
legitimately has no provider credentials — with
`config :brando, :strict_video_provider_config, true` as the opt-in strict
reading. Detection is narrow on purpose (default strategy unconfigured; partial
credentials; credentials without a webhook secret), so a site not using a
provider is never nagged. RED: deleting the "not in use" clause reddens 9 of 12
tests. Zero output across a full e2e run.

The second item found while implementing 9E — `video_upload_available?/1` being
a fourth credential check with a fourth set of rules — is **also closed**: it
now delegates the credential half to `configured?/0` and owns only the webhook
secret and routing values. The divergence turned out to be one-sided, not two:
the empty-string case already agreed, and only a non-binary credential differed.
