defmodule BrandoAdmin.Components.Assets.ProviderVideoUploadTest do
  # A provider upload's `video_upload_complete` comes from the browser. It used
  # to name the video by id, and any video id moved that video out of
  # uploading and onto the field. The browser now sends back the token the
  # server signed when it created the video; every completion handler goes
  # through `complete/3`.
  use Brando.ConnCase

  alias Brando.Factory
  alias Brando.Repo
  alias Brando.Videos.Video
  alias BrandoAdmin.Components.Assets.ProviderVideoUpload

  setup do
    user = Factory.insert(:random_user)

    video =
      Factory.insert(:video,
        type: :cloudflare,
        status: :uploading,
        remote_id: "cf-uid",
        meta: %{"provider" => "cloudflare"},
        creator: user
      )

    {:ok, user: user, video: video}
  end

  defp status(video), do: Repo.get!(Video, video.id).status

  test "completes the upload its token was signed for", %{user: user, video: video} do
    token = ProviderVideoUpload.upload_token(video, user, "ref-1")

    assert {:ok, %Video{id: id}} =
             ProviderVideoUpload.complete(user, %{"request_ref" => "ref-1", "upload_token" => token})

    assert id == video.id
    assert status(video) == :processing
  end

  test "takes the user from an authorization scope too", %{user: user, video: video} do
    token = ProviderVideoUpload.upload_token(video, user, "ref-1")
    scope = Brando.Authorization.Scope.standalone(user)

    assert {:ok, _} = ProviderVideoUpload.complete(scope, %{"request_ref" => "ref-1", "upload_token" => token})
  end

  test "refuses a video id without a token", %{user: user, video: video} do
    assert :error = ProviderVideoUpload.complete(user, %{"request_ref" => "ref-1", "video_id" => video.id})
    assert status(video) == :uploading
  end

  test "refuses a token for another request, another user, or a forged one", %{user: user, video: video} do
    other = Factory.insert(:random_user)
    token = ProviderVideoUpload.upload_token(video, user, "ref-1")

    for {actor, params} <- [
          {user, %{"request_ref" => "ref-2", "upload_token" => token}},
          {other, %{"request_ref" => "ref-1", "upload_token" => token}},
          {nil, %{"request_ref" => "ref-1", "upload_token" => token}},
          {user, %{"request_ref" => "ref-1", "upload_token" => token <> "x"}},
          {user, %{"request_ref" => "ref-1", "upload_token" => 1}}
        ] do
      assert :error = ProviderVideoUpload.complete(actor, params)
    end

    assert status(video) == :uploading
  end

  test "refuses a token signed in another environment", %{user: user, video: video} do
    # Signed with another environment's prefix; this test's own has none
    put_test_env(:tenancy_mode, :multi)

    token =
      Brando.Tenant.with_prefix("tenant_site_other", fn -> ProviderVideoUpload.upload_token(video, user, "ref-1") end)

    put_test_env(:tenancy_mode, :none)

    assert :error = ProviderVideoUpload.complete(user, %{"request_ref" => "ref-1", "upload_token" => token})
    assert status(video) == :uploading
  end

  test "refuses a token naming someone else's video", %{user: user} do
    other = Factory.insert(:random_user)

    others =
      Factory.insert(:video,
        type: :cloudflare,
        status: :uploading,
        remote_id: "cf-other",
        meta: %{"provider" => "cloudflare"},
        creator: other
      )

    token = ProviderVideoUpload.upload_token(others, user, "ref-1")

    assert :error = ProviderVideoUpload.complete(user, %{"request_ref" => "ref-1", "upload_token" => token})
    assert status(others) == :uploading
  end

  test "the destination pushed to the hook carries the token", %{user: user, video: video} do
    payload =
      ProviderVideoUpload.ready_payload(
        %{upload_url: "https://up", video: video, tus_auth: %{a: 1}},
        user,
        "clip.mp4",
        "ref-1"
      )

    assert %{upload_url: "https://up", video_id: id, request_ref: "ref-1", tus_auth: %{a: 1}, upload_token: token} =
             payload

    assert id == video.id
    assert {:ok, _} = ProviderVideoUpload.complete(user, %{"request_ref" => "ref-1", "upload_token" => token})
  end

  # The entry form's video drawer and a transformer complete through
  # `complete/3` too; given someone else's video id they leave it alone.
  describe "the drawer and transformer completions" do
    setup %{video: video} do
      other = Factory.insert(:random_user)
      {:ok, other: other, params: %{"request_ref" => "ref-1", "video_id" => video.id}}
    end

    test "the entry form's drawer", %{other: other, video: video, params: params} do
      socket =
        %Phoenix.LiveView.Socket{}
        |> Phoenix.Component.assign(:current_user, other)
        |> Phoenix.Component.assign(:edit_video, %{field: :clip, video: nil})

      assert {:ok, socket} = BrandoAdmin.Components.Form.update(%{action: :video_upload_complete, upload: params}, socket)
      assert socket.assigns.edit_video.video == nil

      token = ProviderVideoUpload.upload_token(video, video_creator(video), "ref-1")

      assert {:ok, _} =
               BrandoAdmin.Components.Form.update(
                 %{action: :video_upload_complete, upload: Map.put(params, "upload_token", token)},
                 socket
               )

      assert status(video) == :uploading
    end

    test "a transformer", %{other: other, video: video, params: params} do
      socket =
        %Phoenix.LiveView.Socket{}
        |> Phoenix.Component.assign(:current_user, other)
        |> Phoenix.Component.assign(:items, [])

      assert {:noreply, _} = BrandoAdmin.Components.Form.Transformer.handle_event("video_upload_complete", params, socket)
      assert status(video) == :uploading
    end
  end

  defp video_creator(video), do: Repo.get!(Brando.Users.User, video.creator_id)
end
