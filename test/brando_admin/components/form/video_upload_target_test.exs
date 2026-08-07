defmodule BrandoAdmin.Components.Form.VideoUploadTargetTest do
  # Regression coverage for D2/D3 in the form audit — provider (Mux/Bunny/
  # Cloudflare) video uploads resolved their config from the wrong schema.
  #
  # `Form.update(%{action: :get_video_upload_url}, socket)` hand-built
  # `"video:#{inspect(socket.assigns.schema)}:#{field}"`. `socket.assigns.schema`
  # is the ENTRY schema, so a video field living on a nested schema (or a block
  # media ref) resolved against a target that does not exist — silently falling
  # back to the default video config, which is `:local` and therefore has no
  # provider upload at all.
  #
  # The drawer already carries the owning schema on `edit_video.schema`, and the
  # sibling upload trigger in `video_drawer/1` reads it. Both now serialize
  # through `Brando.Assets.ConfigTarget.serialize/1`.
  #
  # Each case is observable without touching a provider: intake validation runs
  # before any HTTP call, and the two schemas below fail it with distinct,
  # deterministic messages.
  use ExUnit.Case, async: false
  use Brando.ConnCase

  alias BrandoAdmin.Components.Form
  alias Phoenix.Component

  defmodule NestedVideoSchema do
    @moduledoc false
    use Brando.Blueprint,
      application: "Brando",
      domain: "Videos",
      schema: "NestedVideoSchema",
      singular: "nested_video_schema",
      plural: "nested_video_schemas",
      gettext_module: Brando.Gettext

    identifier false
    persist_identifier false

    assets do
      asset :clip, :video,
        cfg: %{
          upload_strategy: :mux,
          allow_uploads: true,
          allowed_mimetypes: ["video/mp4"]
        }
    end
  end

  defmodule EntryVideoSchema do
    @moduledoc false
    use Brando.Blueprint,
      application: "Brando",
      domain: "Videos",
      schema: "EntryVideoSchema",
      singular: "entry_video_schema",
      plural: "entry_video_schemas",
      gettext_module: Brando.Gettext

    identifier false
    persist_identifier false

    assets do
      asset :promo, :video,
        cfg: %{
          upload_strategy: :bunny,
          allow_uploads: true,
          allowed_mimetypes: ["video/mp4"]
        }
    end
  end

  setup do
    # Credentials for both providers, so `validate_provider_credentials/1` — 9E's
    # new pre-flight check, which runs *before* `validate_intake/4` — is not the
    # thing these tests observe. Without them every case below reports "Video
    # provider is not configured" and the mimetype signal each one relies on to
    # identify the resolved config never surfaces.
    Brando.Test.Support.put_test_env(Brando.Videos.Uploaders.Mux,
      access_token_id: "id",
      access_token_secret: "secret"
    )

    Brando.Test.Support.put_test_env(Brando.Videos.Uploaders.Bunny, api_key: "key")

    {:ok, user: Brando.Factory.insert(:random_user)}
  end

  defp form_socket(entry_schema, edit_video, user) do
    %Phoenix.LiveView.Socket{}
    |> Component.assign(:schema, entry_schema)
    |> Component.assign(:edit_video, edit_video)
    |> Component.assign(:current_user, user)
  end

  defp request_upload(socket, filename, mime_type) do
    {:ok, socket} =
      Form.update(
        %{
          action: :get_video_upload_url,
          upload_request: %{
            "request_ref" => "ref-1",
            "filename" => filename,
            "size" => 1_000,
            "mime_type" => mime_type
          }
        },
        socket
      )

    socket
  end

  defp pushed_error(socket) do
    socket.private.live_temp
    |> Map.get(:push_events, [])
    |> Enum.find_value(fn
      ["video_upload_url_error", payload | _] -> payload
      _ -> nil
    end)
  end

  test "the config target is built from the drawer's schema, not the entry's", ctx do
    # The entry is a Page; the open drawer edits a :clip on NestedVideoSchema.
    # Only NestedVideoSchema restricts mimetypes to mp4, so a .mov reaching that
    # rejection proves the nested schema's config was the one resolved.
    socket =
      form_socket(
        Brando.Pages.Page,
        %{schema: NestedVideoSchema, field: :clip, path: [], relation_field: nil, video: nil},
        ctx.user
      )

    error = socket |> request_upload("clip.mov", "video/quicktime") |> pushed_error()

    assert error.request_ref == "ref-1"
    assert error.error =~ "Rejected file type [video/quicktime]"

    # Before the fix the target was "video:Brando.Pages.Page:clip", which has no
    # blueprint asset behind it, so the default (:local) config answered instead:
    refute error.error =~ "not available for provider uploads"
  end

  test "an edit_video without a :schema still falls back to the entry schema", ctx do
    socket =
      form_socket(
        EntryVideoSchema,
        %{field: :promo, path: [], relation_field: nil, video: nil},
        ctx.user
      )

    error = socket |> request_upload("promo.mov", "video/quicktime") |> pushed_error()

    assert error.error =~ "Rejected file type [video/quicktime]"
  end

  test "an unserializable target reports an upload error instead of raising", ctx do
    # `serialize/1` raises on a missing field segment. A hard match here would
    # take the whole entry form process down (the A2 class of bug).
    socket =
      form_socket(
        Brando.Pages.Page,
        %{schema: NestedVideoSchema, field: nil, path: [], relation_field: nil, video: nil},
        ctx.user
      )

    error = socket |> request_upload("clip.mp4", "video/mp4") |> pushed_error()

    assert error.error == "Invalid video upload target"
    assert error.filename == "clip.mp4"
    assert error.request_ref == "ref-1"
  end

  test "a missing provider credential is reported, not allowed to kill the form", ctx do
    # Control for the target resolution — an allowed mimetype gets past the
    # mimetype check and reaches the provider strategy — and coverage for a
    # defect found while writing it: `Mux.api_request/3` RAISES on missing
    # credentials, and unrescued that exception takes the entry form process
    # down with every unsaved change in it (the A2 class).
    #
    # What changed in 9E is *where* that is caught. It used to be `Form`'s local
    # rescue turning the RuntimeError back into a tuple, which is why this
    # asserted the raise's own text. Now `validate_provider_credentials/1`
    # rejects the pick during pre-flight validation and the provider is never
    # called — so the assertion is the fixed user-facing string, and the raise
    # it used to observe is unreachable from here by design.
    Brando.Test.Support.put_test_env(Brando.Videos.Uploaders.Mux, [])

    socket =
      form_socket(
        Brando.Pages.Page,
        %{schema: NestedVideoSchema, field: :clip, path: [], relation_field: nil, video: nil},
        ctx.user
      )

    error = socket |> request_upload("clip.mp4", "video/mp4") |> pushed_error()

    # got past intake — so the nested schema's :mux strategy was the one resolved
    refute error.error =~ "Rejected file type"
    refute error.error =~ "not available for provider uploads"
    assert error.error == "Video provider is not configured. Check server configuration."
    refute error.error =~ "provider_not_configured"
  end
end
