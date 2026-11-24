defmodule Brando.SoftDelete.PurgeEntryTest do
  # Delete permanently from the trash (#3927), as `Query.purge_entry/4`
  # deletes one row: in its environment only, and a provider video as the
  # scheduled purge deletes it.
  # Not async: provider configuration is application env.
  use Brando.ConnCase, async: false

  import ExUnit.CaptureLog
  import Plug.Conn

  alias Brando.Factory
  alias Brando.Pages.Page
  alias Brando.SoftDelete.Query
  alias Brando.Tenant
  alias Brando.Videos.Uploaders.Mux
  alias Brando.Videos.Video

  setup do
    %{user: Factory.insert(:random_user, role: :superuser)}
  end

  describe "with several environments" do
    @prefixes ["tenant_purge3927_production", "tenant_purge3927_staging"]

    setup do
      put_test_env(:tenancy_mode, :multi)
      on_exit(fn -> Tenant.put_prefix(nil) end)

      for prefix <- @prefixes do
        :ok = Brando.Environments.Schema.create(prefix)
        :ok = Brando.TenantCloners.clone_structure("public", prefix)
      end

      :ok
    end

    defp trashed_in(prefix, id, deleted_at) do
      Tenant.with_prefix(prefix, fn ->
        Brando.Repo.insert!(%Page{
          id: id,
          title: "Page",
          uri: "page",
          language: :en,
          template: "default.html",
          status: :draft,
          deleted_at: deleted_at
        })
      end)
    end

    defp in_env(prefix, fun), do: Tenant.with_prefix(prefix, fun)

    test "the same id in another environment is left, and its own trash time is not this one's", %{user: user} do
      [production, staging] = @prefixes
      shown = DateTime.utc_now(:second)
      trashed_in(production, 4242, shown)
      trashed_in(staging, 4242, DateTime.add(shown, -60, :second))

      # Staging's row went to the trash at another time: not the row shown
      assert {:error, :not_in_trash} = in_env(staging, fn -> Query.purge_entry(Page, 4242, shown, user) end)
      assert :ok = in_env(production, fn -> Query.purge_entry(Page, 4242, shown, user) end)

      refute in_env(production, fn -> Brando.Repo.get(Page, 4242) end)
      assert in_env(staging, fn -> Brando.Repo.get(Page, 4242) end)
    end
  end

  describe "a video its provider deletes on purge" do
    setup do
      put_test_env(:tenancy_mode, :none)

      put_test_env(Mux,
        access_token_id: "id",
        access_token_secret: "secret",
        delete_remote_on: :on_purge,
        req_options: [plug: {Req.Test, Mux}, retry: false]
      )

      video =
        Brando.Repo.insert!(%Video{
          type: :mux,
          title: "Video",
          status: :ready,
          meta: %{"mux" => %{"asset_id" => "asset-1"}},
          deleted_at: DateTime.utc_now(:second)
        })

      %{video: video}
    end

    defp answer(status) do
      me = self()

      Req.Test.stub(Mux, fn conn ->
        send(me, {:provider, conn.method})
        conn |> put_resp_content_type("application/json") |> send_resp(status, ~s({}))
      end)
    end

    test "is deleted at its provider too, as the scheduled purge deletes it", %{user: user, video: video} do
      answer(204)

      assert :ok = Query.purge_entry(Video, video.id, video.deleted_at, user)

      assert_received {:provider, "DELETE"}
      refute Brando.Repo.get(Video, video.id)
    end

    test "stays when its provider could not answer, to be tried again", %{user: user, video: video} do
      answer(503)

      capture_log(fn ->
        assert {:error, {:retry, _}} = Query.purge_entry(Video, video.id, video.deleted_at, user)
      end)

      assert Brando.Repo.get!(Video, video.id).deleted_at
    end

    test "a video something still refers to says so, and the provider is left alone", %{user: user, video: video} do
      answer(204)
      # An application's own foreign key to videos, which the purge does not clear
      BrandoIntegration.Repo.query!("ALTER TABLE projects ADD COLUMN purge_test_video_id bigint REFERENCES videos(id)")

      BrandoIntegration.Repo.query!(
        "INSERT INTO projects (title, slug, language, purge_test_video_id, inserted_at, updated_at) " <>
          "VALUES ('Project', 'project', 'en', $1, now(), now())",
        [video.id]
      )

      capture_log(fn ->
        assert {:error, {:referenced, _constraint}} = Query.purge_entry(Video, video.id, video.deleted_at, user)
      end)

      refute_received {:provider, _}
      assert Brando.Repo.get!(Video, video.id).deleted_at
    end

    test "a stale trash time leaves the provider alone", %{user: user, video: video} do
      answer(204)

      capture_log(fn ->
        assert {:error, :not_in_trash} =
                 Query.purge_entry(Video, video.id, DateTime.add(video.deleted_at, -60, :second), user)
      end)

      refute_received {:provider, _}
      assert Brando.Repo.get!(Video, video.id)
    end
  end
end
