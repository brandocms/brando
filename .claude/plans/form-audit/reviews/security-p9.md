# Security Audit — Phase 9 (`HEAD~5..HEAD`)

Scope: `lib/brando/videos/uploaders/cloudflare.ex`, `lib/brando_admin/components/form.ex`,
`lib/brando_admin/components/form/video_drawer.ex`, `test/brando/videos/provider_client_test.exs`.

## Executive summary

No BLOCKER. The credential-raise decision itself is safe: all three provider
raise messages are static heredocs that interpolate nothing, so no token,
account id or config map reaches a log, an error tracker or a browser.

Two findings, both consequences of the raise reaching call sites that were not
updated with it. One WARNING (availability / unsaved-work loss), one
SUGGESTION (verbatim exception message shipped to the admin browser).

Phase 8's SEC-1 (Bunny redirect key leak) is **not persistent** — the guard and
its regression test are intact and untouched by this phase.

---

## Findings

### W1 — Cloudflare's new raise reaches two call sites that have no rescue

- **Severity**: WARNING
- **Location**: `lib/brando_admin/components/video_picker.ex:463`,
  `lib/brando_admin/components/form/transformer.ex:909`
- **Issue**: `08c371da2` moved Cloudflare from `{:error, :not_configured}` to a
  `raise`, and only one of the three `Brando.Videos.Uploader.initiate_upload/3`
  call sites is protected. `form.ex:5816` `initiate_provider_upload/5` has a
  broad `rescue` written for exactly this class (its own comment cites D3/A2).
  `video_picker.ex` and `transformer.ex` call the dispatcher bare.

  Concrete path on a site configured `upload_strategy: :cloudflare` with a
  missing or empty `account_id`/`api_token`: the editor picks a file in the
  video picker → `handle_event("get_video_upload_url", …)` →
  `Cloudflare.api_request/4` raises `RuntimeError` → the LiveComponent's parent
  LiveView process exits → every unsaved change in the open form is gone. Before
  this commit the same misconfiguration returned `{:error, :not_configured}` and
  was rendered as a `video_upload_url_error` toast with the form intact.

  This is not new for Mux/Bunny (they already raised, so those two call sites
  were already exposed) — but the commit widened the exposure to the third
  provider without widening the rescue. That is the part this phase owns.

- **Fix**: extract the rescue that already exists in `form.ex:5816-5833` and
  route all three call sites through it, e.g.

  ```elixir
  # Brando.Videos.Uploader
  def safe_initiate_upload(filename, user, opts) do
    initiate_upload(filename, user, opts)
  rescue
    exception ->
      Logger.error("Video provider upload raised: " <>
        Exception.format(:error, exception, __STACKTRACE__))
      {:error, :provider_unavailable}
  end
  ```

  then `form.ex`, `video_picker.ex` and `transformer.ex` all call
  `safe_initiate_upload/3` and keep their existing `{:error, reason}` branches.

- **Note (good)**: the raise fires in `api_request/4` *before*
  `create_video_record/4`, so a misconfigured deploy leaves no orphaned
  `:uploading` Video row. Failure-path consistency check passes.

### S1 — The raise message is pushed verbatim to the admin browser

- **Severity**: SUGGESTION
- **Location**: `lib/brando_admin/components/form.ex:5832` →
  `:5741` → `:5886`
- **Issue**: `initiate_provider_upload/5` returns
  `{:error, Exception.message(exception)}`. That binary matches
  `extract_video_error_message/1`'s "plain string error" clause
  (`form.ex:5741`), which returns it untouched, and it is then pushed to the
  JS hook: `push_event(socket, "video_upload_url_error", %{error: error_message, …})`.

  So a Cloudflare-misconfigured site now delivers the whole heredoc —
  `config :brando, Brando.Videos.Uploaders.Cloudflare, account_id:
  System.get_env("CLOUDFLARE_ACCOUNT_ID"), …` — into the admin's browser, where
  the pre-0.54.0 behaviour delivered the string `":not_configured"`.

  No secret **value** is in that message; what leaks is module names and env var
  names, to an already-authenticated admin. Low impact on its own. It is worth
  fixing because the `rescue` is deliberately broad ("three provider clients
  with three failure vocabularies"), so this is a general channel: any future
  exception raised anywhere under `initiate_upload/3` has its message forwarded
  to a client, and not every exception message is as careful as these three.

- **Fix**: keep the detail in the log (it is already logged with a full
  stacktrace one line above) and return an opaque reason:

  ```elixir
  rescue
    exception ->
      Logger.error("Video provider upload raised: " <>
        Exception.format(:error, exception, __STACKTRACE__))

      {:error, :provider_unavailable}
  end
  ```

  with a matching `extract_video_error_message(:provider_unavailable)` clause
  returning a gettext string.

- **OWASP**: A09:2021 (Security Logging and Monitoring Failures) / CWE-209
  Generation of Error Message Containing Sensitive Information.

---

## Verified clean

**Q1 — Do the raises leak credentials? No.** All three messages are static
heredocs with no interpolation of any kind:
`cloudflare.ex:284-290`, `mux.ex:545-551`, `bunny.ex:403-410`. None inspects a
config map, a struct, or a partial token. Cloudflare additionally reads
credentials into locals *before* the check but never names them in the message.

**Q3 — Test fixtures.** `provider_client_test.exs` uses only obviously-fake
values: `"id"`/`"secret"` (Mux), `"bunny-key"`/`library_id: "4242"`/
`"vz-test.b-cdn.net"`, `"account-id"`/`"api-token"` (Cloudflare), and
`"hijacked"` for the precedence tests. Nothing real-looking, no live account id,
no key-shaped string. `with_config/2` correctly restores by *deleting* the key
when there was none, so no test leaves credentials in the application env for
the next test.

**Q4 — SEC-1 did not regress. NOT PERSISTENT.** `redirect: false` is present on
all three branches of Bunny's `api_request/3` (`bunny.ex:440, 443, 446`) with
its rationale comment intact. It is config-proof because `ReqOptions.merge/2` is
`Keyword.merge(configured || [], built)` — built wins — and `ReqOptions` itself
is unchanged by this phase (`req_options.ex:89-96`). The regression test at
`provider_client_test.exs:176-206` still asserts
`{:request, "video.bunnycdn.com", ["bunny-key"]}` and
`refute_received {:request, "evil.example.com", _}`. Three precedence tests
(`:222`, `:248`, `:268`) pin that none of the three providers' auth headers can
be replaced from `runtime.exs`.

**Q5 — `video_drawer.ex`.** Clean on all three checks.
- No `raw/1`, no `Phoenix.HTML.raw`, no `{:safe, …}` anywhere in the file. Every
  interpolation is HEEx-escaped: `@video_filename` (`:278`),
  `@edit_video.video.remote_id` (`:333`), `@video.thumbnail.path` (`:88`),
  dimensions (`:282`, `:337`).
- No user URL reaches a `src`/`href`. `source_url` is rendered only as an
  `Input.text` value (`:317-321`), i.e. an escaped attribute, never as an embed
  or link target. There is no iframe/embed markup in this module at all.
- **No authorization was lost in the extraction.** The gate stayed in `Form`:
  `handle_event("save_video", …)` (`form.ex:3700`) re-checks
  `external_video_urls_allowed?/1` server-side before delegating, so hiding the
  external tab in markup is defence-in-depth, not the control. The
  `save_video_authorized` clause additionally pattern-matches
  `video_save_authorized?: true` in assigns, so a client pushing
  `save_video_authorized` directly falls through to the no-op clause at
  `form.ex:3789`. The saved video is taken from `socket.assigns.edit_video.video`
  (server state), not from a client param — no IDOR. `@myself` is the parent
  `Form`'s CID, passed explicitly at the call site (`form.ex:2069-2077`), so
  every `phx-target` in the drawer still lands on the authorized handlers.

Also checked and clean across the changed files: `String.to_atom` (only
`to_existing_atom` with `rescue ArgumentError`, `form.ex:4779, 4883, 4931`),
SQL interpolation, `binary_to_term`, CSRF, hardcoded secrets.

---

## Pre-existing (one line each, not this phase)

- `lib/brando_admin/components/video_picker.ex:487` — `error: inspect(reason)`
  pushes a raw internal error term to the browser.
- `lib/brando_admin/components/form.ex:5747` — `extract_video_error_message/1`
  fallback `inspect(error)`, same channel as S1 for non-binary reasons.
- `lib/brando_admin/components/form/video_drawer.ex:256` —
  `ConfigTarget.serialize/1` runs at render time with no rescue, where the
  sibling `form.ex:5805` has one; an `ArgumentError` here kills the form render.
  Robustness, not security.
- `lib/brando/videos/uploaders/bunny.ex:221` — TUS signature is a bare
  `SHA256(library_id <> api_key <> expire <> guid)` rather than an HMAC. This is
  Bunny's documented scheme; noted only so it is not mistaken for our choice.

## Tools for the maintainer to run

- `mix sobelow --exit medium`
- `mix deps.audit`
- `mix hex.audit`
