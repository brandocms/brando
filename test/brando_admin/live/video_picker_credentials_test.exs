defmodule BrandoAdmin.VideoPickerCredentialsTest do
  @moduledoc """
  The Phase 9 review's BLOCKER, pinned against a real mounted LiveView.

  `Brando.Videos.Uploader.initiate_upload/3` has three call sites and only
  `Form`'s was rescued. 0.54.0 took Cloudflare from `{:error, :not_configured}`
  to a raise, which is the right contract for a deploy-time config error — but
  the check lived in `api_request/4`, so it fired at *file-pick* time. A pick in
  `VideoPicker` or `Form.Transformer` therefore killed the entry form process
  and every unsaved change in it. `Form`'s own comment had named that hazard by
  name; 0.54.0 widened who could trigger it without widening the guard.

  9E moves the check into `Brando.Uploads.validate_provider_video_intake/2`,
  beside the other pre-flight validators, so the pick is rejected before any
  provider call. The raises stay exactly as decided and become a last-resort
  invariant guard the admin path cannot reach.

  **This asserts the process is alive, and that is deliberate.** The audit's
  carried lesson is that a claim whose only check is a re-read is not checked —
  reading the `with` chain and concluding the view must survive is the move that
  kept C4 open for nine phases. So: mount it, pick a video against a
  credential-less provider, and look at the process.

  ## Why the credentials are removed *after* mount

  Found while writing this, and it narrows the review's reachability claim
  without closing it. All three upload surfaces — picker, drawer, transformer —
  hide their upload trigger behind `Brando.Uploads.video_upload_available?/1`,
  so a wholly credential-less deploy renders no button to click.

  That gate is **a render-time snapshot, not a guard**. It is computed in
  `update/2` and never re-checked in `handle_event/3`, while the providers read
  their config at *call* time. So a credential removed, rotated or
  mis-deployed after the component last updated leaves a live trigger in a DOM
  that will happily push the event — which is what this setup models, and which
  is the plan's own recorded open item ("config is read at call time, not
  boot") arriving as a live defect rather than a note.

  It also disagrees with `configured?/0` in both directions:
  `upload_available?/1` additionally demands a `webhook_secret`, and its
  `present?/1` accepts any non-nil non-empty term where the providers' accepts
  only a non-empty binary. A non-binary `account_id` renders the button and
  fails the provider check.

  MUTATION: drop `:ok <- validate_provider_credentials(cfg)` from the `with`
  chain in `Brando.Uploads.validate_provider_video_intake/2`. Both tests redden,
  the first on `Process.alive?/1` — the view having died of the RuntimeError
  the provider raises.
  """
  use Brando.LiveCase

  @credentials [account_id: "acct", api_token: "token", webhook_secret: "whsec"]

  setup %{current_user: user} do
    # Mount with a complete config so the upload trigger renders at all.
    put_test_env(Brando.Videos.Uploaders.Cloudflare, @credentials)
    put_test_env(:default_video_upload_strategy, :cloudflare)

    {:ok, page: Factory.insert(:page, creator: user)}
  end

  # The credentials go away after the DOM is rendered — a rotation, a bad
  # deploy, a secret dropped from the environment. The trigger is still on the
  # page, and the provider is read at call time.
  defp drop_credentials do
    put_test_env(Brando.Videos.Uploaders.Cloudflare, [])
  end

  # Routing is the whole point here, so it is done the way the browser does it.
  # `providerVideoUploader.js` calls `pushEventTo(this.el.dataset.target, …)`,
  # and `data-target` renders as the picker's CID — so the CID is read out of
  # the DOM and handed to `with_target/2`, which accepts one directly.
  #
  # The two obvious alternatives both silently test the wrong thing:
  # `element(…) |> render_hook(…)` reads only `phx-target` (absent here, since
  # the hook pushes programmatically) and `with_target("#video-picker")` selects
  # the drawer div, which carries no `data-phx-component`. Both fall through to
  # the *root* LiveView, where `hooks.ex:895` forwards to `Form` — the one call
  # site that was already rescued. The test would then pass without ever
  # reaching the defect. It did, until this was chased down.
  defp picker_cid(view) do
    view
    |> render()
    |> Floki.parse_document!()
    |> Floki.attribute("#video-provider-uploader-video-picker", "data-target")
    |> case do
      [cid] ->
        String.to_integer(cid)

      [] ->
        flunk("""
        the picker's provider-upload trigger is not in the DOM, so this test \
        cannot reach the call site it exists for. It is gated on \
        `video_upload_available?`, which needs a complete credential set \
        (webhook_secret included) at mount.\
        """)
    end
  end

  defp pick_video(view) do
    view
    |> with_target(picker_cid(view))
    |> render_hook("get_video_upload_url", %{
      "request_ref" => "ref-1",
      "filename" => "clip.mp4",
      "size" => 1_000,
      "mime_type" => "video/mp4"
    })
  end

  test "a pick against a credential-less provider leaves the LiveView alive", %{
    conn: conn,
    page: page
  } do
    {view, _html} = live_form(conn, "/admin/pages/update/#{page.id}")

    assert Process.alive?(view.pid), "the form died before the pick — fixture problem, not a result"

    drop_credentials()
    pick_video(view)

    # The assertion the blocker is about. Pre-9E this is false: `api_request/4`
    # raises inside `handle_event/3` and takes the LiveView down, along with
    # every unsaved change the editor was holding.
    assert Process.alive?(view.pid),
           "the pick killed the form process — a provider raise reached an unrescued call site"

    # Still serving, not merely un-exited.
    assert render(view) =~ "video-picker"
  end

  test "the pick is reported to the browser as an upload error", %{conn: conn, page: page} do
    {view, _html} = live_form(conn, "/admin/pages/update/#{page.id}")

    drop_credentials()
    pick_video(view)

    assert_push_event(view, "video_upload_url_error", payload)

    assert payload.request_ref == "ref-1"
    assert payload.filename == "clip.mp4"

    # A fixed string, not `inspect/1` of the raw term. The picker pushed
    # `inspect(reason)` straight to the browser until 9E-3 — the same channel as
    # the review's SUGGESTION 1, and strictly worse than the string `Form` used.
    assert payload.error == "Video provider is not configured. Check server configuration."
    refute payload.error =~ ":provider_not_configured"
  end
end
