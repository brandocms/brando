defmodule Brando.Videos.ProviderLibrarySharingTest do
  # Audit NV6: the provider accounts are the installation's, so in a multi-site
  # installation what one site may list, add and delete at the provider follows
  # the sites' provider library groups.
  use Brando.ConnCase, async: false

  import Brando.Test.Support, only: [put_test_env: 2]
  import Plug.Conn

  alias Brando.Authorization.Migration
  alias Brando.Factory
  alias Brando.Repo
  alias Brando.Tenant
  alias Brando.Tenant.Cache
  alias Brando.Tenant.Registry
  alias Brando.Videos.ProviderLibrary
  alias Brando.Videos.Uploader
  alias Brando.Videos.Uploaders.Bunny
  alias Brando.Videos.Uploaders.Cloudflare
  alias Brando.Videos.Uploaders.Mux
  alias Brando.Videos.Uploaders.Vimeo
  alias Brando.Videos.Video
  alias Ecto.Adapters.SQL

  setup do
    put_test_env(Mux, [])
    put_test_env(Bunny, [])
    put_test_env(Cloudflare, [])
    put_test_env(Vimeo, access_token: "vimeo-token", req_options: [plug: {Req.Test, Vimeo}])
    put_test_env(:tenancy_mode, :multi)
    Cache.clear()

    me = self()

    Req.Test.stub(Vimeo, fn conn ->
      send(me, {:vimeo, conn.method, conn.request_path})

      case {conn.method, conn.request_path} do
        {"GET", "/me/videos"} ->
          Req.Test.json(conn, %{"paging" => %{"next" => nil}, "data" => Enum.map(~w(1 2 3 4), &vimeo_video/1)})

        {"GET", "/videos/" <> id} ->
          Req.Test.json(conn, vimeo_video(id))

        {"DELETE", "/videos/" <> _id} ->
          send_resp(conn, 204, "")
      end
    end)

    on_exit(fn ->
      Tenant.put_prefix(nil)
      Cache.clear()
    end)

    # Alpha is in no group; Beta and Gamma share "news"; Delta is in "other".
    alpha = site("Alpha", "nv-alpha", nil)
    beta = site("Beta", "nv-beta", "news")
    gamma = site("Gamma", "nv-gamma", "news")
    delta = site("Delta", "nv-delta", "other")

    # Uploaded through Brando by one site each, and "4" by nobody.
    held = %{
      alpha: uploaded(alpha, "1"),
      gamma: uploaded(gamma, "2"),
      delta: uploaded(delta, "3")
    }

    {:ok, user: Factory.insert(:random_user), sites: %{alpha: alpha, beta: beta, gamma: gamma, delta: delta}, held: held}
  end

  describe "a site in no group" do
    test "gets no provider library, and adding is refused", %{sites: sites, user: user} do
      as_site(sites.alpha, fn ->
        assert ProviderLibrary.providers() == []
        assert {:error, {:unknown_strategy, :vimeo}} = ProviderLibrary.list(:vimeo)
        assert {:error, {:unknown_strategy, :vimeo}} = ProviderLibrary.import(:vimeo, "2", user)
        assert {:error, {:unknown_strategy, :vimeo}} = ProviderLibrary.import(:vimeo, "4", user)
        assert Repo.aggregate(Video, :count) == 1
      end)

      refute_received {:vimeo, _method, _path}
    end

    test "outside any site, nothing is offered", %{user: user} do
      assert Tenant.current_prefix() == nil
      assert ProviderLibrary.providers() == []
      assert {:error, {:unknown_strategy, :vimeo}} = ProviderLibrary.import(:vimeo, "4", user)
    end
  end

  describe "a site in a group" do
    test "lists what its group holds and what no site holds", %{sites: sites} do
      as_site(sites.beta, fn ->
        assert [%{strategy: :vimeo}] = ProviderLibrary.providers()
        assert {:ok, %{items: items}} = ProviderLibrary.list(:vimeo)
        assert Enum.map(items, & &1.remote_id) == ["2", "4"]
      end)

      as_site(sites.delta, fn ->
        assert {:ok, %{items: items}} = ProviderLibrary.list(:vimeo)
        assert items |> Enum.map(& &1.remote_id) |> Enum.sort() == ["3", "4"]
      end)
    end

    test "adds a video its group holds, and one no site holds", %{sites: sites, user: user} do
      as_site(sites.beta, fn ->
        assert {:ok, %Video{meta: %{"imported" => true}}} = ProviderLibrary.import(:vimeo, "2", user)
        assert {:ok, %Video{meta: %{"imported" => true}}} = ProviderLibrary.import(:vimeo, "4", user)
        assert Repo.aggregate(Video, :count) == 2
      end)
    end

    test "is refused another group's video or an isolated site's, by id", %{sites: sites, user: user} do
      as_site(sites.beta, fn ->
        assert {:error, :not_found} = ProviderLibrary.import(:vimeo, "1", user)
        assert {:error, :not_found} = ProviderLibrary.import(:vimeo, "3", user)
        assert Repo.aggregate(Video, :count) == 0
      end)

      as_site(sites.delta, fn ->
        assert {:error, :not_found} = ProviderLibrary.import(:vimeo, "2", user)
      end)

      # Refused before Vimeo is asked about it.
      refute_received {:vimeo, "GET", "/videos/" <> _id}
    end

    test "a video held both in and outside the group is shared", %{sites: sites, user: user} do
      as_site(sites.delta, fn -> uploaded_here("2") end)

      as_site(sites.beta, fn ->
        assert {:ok, %{items: items}} = ProviderLibrary.list(:vimeo)
        assert "2" in Enum.map(items, & &1.remote_id)
        assert {:ok, _video} = ProviderLibrary.import(:vimeo, "2", user)
      end)
    end

    test "a site that leaves the group stops sharing at once", %{sites: sites, user: user} do
      {:ok, _gamma} = Registry.put_provider_library_group(sites.gamma, "", :system)

      as_site(sites.beta, fn ->
        assert {:ok, %{items: items}} = ProviderLibrary.list(:vimeo)
        assert Enum.map(items, & &1.remote_id) == ["4"]
        assert {:error, :not_found} = ProviderLibrary.import(:vimeo, "2", user)
      end)
    end

    test "when it cannot be told who holds a video, none is listed or added", %{sites: sites, user: user} do
      broken = site("Broken", "nv-broken", "news", tables: false)
      assert broken.provider_library_group == "news"

      as_site(sites.beta, fn ->
        assert {:error, :holdings_unavailable} = ProviderLibrary.list(:vimeo)
        assert {:error, :holdings_unavailable} = ProviderLibrary.import(:vimeo, "4", user)
      end)
    end
  end

  describe "deleting at the provider" do
    test "is refused while another site holds the video", %{sites: sites, held: held, user: user} do
      as_site(sites.beta, fn -> {:ok, _added} = ProviderLibrary.import(:vimeo, "2", user) end)

      as_site(sites.gamma, fn ->
        assert Uploader.get_delete_timing(held.gamma) == :on_purge
        assert {:error, :held_by_another_site} = Uploader.delete_remote(held.gamma)
      end)

      refute_received {:vimeo, "DELETE", _path}

      # Once Beta's record is gone, Gamma's own delete reaches Vimeo.
      as_site(sites.beta, fn -> Repo.delete_all(Video) end)
      as_site(sites.gamma, fn -> assert :ok = Uploader.delete_remote(held.gamma) end)
      assert_received {:vimeo, "DELETE", "/videos/2"}
    end

    test "a soft-deleted record elsewhere still holds it", %{sites: sites, held: held} do
      as_site(sites.delta, fn ->
        "2" |> uploaded_here() |> Ecto.Changeset.change(deleted_at: DateTime.utc_now(:second)) |> Repo.update!()
      end)

      as_site(sites.gamma, fn ->
        assert {:error, :held_by_another_site} = Uploader.delete_remote(held.gamma)
      end)

      refute_received {:vimeo, "DELETE", _path}
    end

    test "the site's own other environments do not hold it from another site", %{sites: sites, held: held} do
      staging = environment(sites.gamma, "staging")
      Tenant.with_prefix(Tenant.prefix(sites.gamma, staging), fn -> uploaded_here("2") end)

      as_site(sites.gamma, fn -> assert :ok = Uploader.delete_remote(held.gamma) end)
      assert_received {:vimeo, "DELETE", "/videos/2"}
    end

    test "is refused when it cannot be told who holds it", %{sites: sites, held: held} do
      site("Broken", "nv-broken", nil, tables: false)

      as_site(sites.alpha, fn ->
        assert {:error, :holdings_unavailable} = Uploader.delete_remote(held.alpha)
      end)

      refute_received {:vimeo, "DELETE", _path}
    end
  end

  describe "single-site installations" do
    test "list and add the whole account, and delete as before", %{sites: sites, held: held, user: user} do
      for mode <- [:single, :none] do
        put_test_env(:tenancy_mode, mode)

        as_site(sites.alpha, fn ->
          assert [%{strategy: :vimeo}] = ProviderLibrary.providers()
          assert {:ok, %{items: items}} = ProviderLibrary.list(:vimeo)
          assert Enum.map(items, & &1.remote_id) == ~w(1 2 3 4)
          assert {:ok, %Video{}} = ProviderLibrary.import(:vimeo, "3", user)
          # Another site's record does not count without several sites.
          assert :ok = Uploader.delete_remote(held.gamma)
        end)

        assert_received {:vimeo, "DELETE", "/videos/2"}
      end
    end
  end

  describe "choosing a site's group" do
    test "only an installation superuser may, in legacy mode", %{sites: sites} do
      for role <- [:admin, :editor, :user] do
        assert {:error, changeset} =
                 Registry.put_provider_library_group(sites.alpha, "news", Factory.insert(:random_user, role: role))

        assert [provider_library_group: _message] = changeset.errors
      end

      assert {:error, _changeset} = Registry.put_provider_library_group(sites.alpha, "news", nil)
      assert Registry.get_site(sites.alpha.id).provider_library_group == nil

      superuser = Factory.insert(:random_user, role: :superuser)

      assert {:ok, %{provider_library_group: "news"}} =
               Registry.put_provider_library_group(sites.alpha, " news ", superuser)

      assert {:ok, %{provider_library_group: nil}} = Registry.put_provider_library_group(sites.alpha, "", superuser)

      assert {:error, changeset} = Registry.put_provider_library_group(sites.alpha, "News Room", superuser)
      assert [provider_library_group: _format] = changeset.errors
    end

    test "in groups mode, the Superuser group decides", %{sites: sites} do
      put_test_env(:authorization_mode, :groups)
      owner = Factory.insert(:random_user, role: :superuser)
      {:ok, _} = Migration.run()

      # Holds the legacy role, but is in no Superuser group.
      assert {:error, _changeset} =
               Registry.put_provider_library_group(sites.alpha, "news", Factory.insert(:random_user, role: :superuser))

      assert {:ok, %{provider_library_group: "news"}} = Registry.put_provider_library_group(sites.alpha, "news", owner)
    end

    test "an ordinary site update does not change it", %{sites: sites} do
      assert {:ok, site} = Registry.update_site(sites.beta, %{provider_library_group: nil, name: "Beta renamed"})
      assert site.provider_library_group == "news"
    end
  end

  defp site(name, key, group, opts \\ []) do
    {:ok, site} =
      Registry.create_site(%{
        name: name,
        key: key,
        languages: ["en"],
        default_language: "en",
        status: :active,
        delivery_mode: :dynamic
      })

    {:ok, site} = Registry.put_provider_library_group(site, group, :system)
    environment(site, "production", opts)
    Registry.get_site(site.id)
  end

  # The content tables' structure, as an environment has them; with
  # `tables: false`, a schema with none, which the holdings cannot read.
  defp environment(site, key, opts \\ []) do
    {:ok, environment} = Registry.create_environment(site, %{name: key, key: key, live: key == "production"})
    prefix = Tenant.prefix(site, environment)
    SQL.query!(Repo.repo(), ~s(CREATE SCHEMA "#{prefix}"))
    if Keyword.get(opts, :tables, true), do: Enum.each(content_tables(), &clone_table(prefix, &1))
    environment
  end

  defp content_tables do
    %{rows: rows} = SQL.query!(Repo.repo(), "SELECT tablename FROM pg_tables WHERE schemaname = 'public'")
    rows |> List.flatten() |> Enum.reject(&Tenant.SharedTables.member?/1)
  end

  defp clone_table(prefix, table) do
    escaped = String.replace(table, "\"", "\"\"")
    SQL.query!(Repo.repo(), ~s|CREATE TABLE "#{prefix}"."#{escaped}" (LIKE public."#{escaped}" INCLUDING ALL)|)
  end

  defp as_site(site, fun) do
    site = Registry.get_site(site.id)
    environment = Enum.find(site.environments, & &1.live)
    Tenant.with_prefix(Tenant.prefix(site, environment), fun)
  end

  defp uploaded(site, remote_id), do: as_site(site, fn -> uploaded_here(remote_id) end)

  defp uploaded_here(remote_id) do
    Repo.insert!(%Video{
      type: :vimeo_account,
      title: "Video #{remote_id}",
      remote_id: remote_id,
      status: :ready,
      meta: %{"provider" => "vimeo", "vimeo" => %{"video_id" => remote_id}}
    })
  end

  defp vimeo_video(id) do
    %{
      "uri" => "/videos/#{id}",
      "name" => "Video #{id}",
      "link" => "https://vimeo.com/#{id}",
      "status" => "available",
      "transcode" => %{"status" => "complete"},
      "width" => 1280,
      "height" => 720,
      "duration" => 30,
      "created_time" => "2026-09-01T10:00:00+00:00",
      "files" => [%{"quality" => "hls", "link" => "https://player.vimeo.com/external/#{id}.m3u8?s=x"}]
    }
  end
end
