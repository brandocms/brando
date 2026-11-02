defmodule BrandoAdmin.VideoPickerLibrarySitesTest do
  @moduledoc """
  Audit NV6: "Add from <provider>" in a multi-site installation, driven through
  a real entry form on site Beta by an editor who may enter Beta alone. Site
  Alpha uploaded video 42 to the shared Vimeo account.
  """
  use Brando.LiveCase

  alias Brando.Repo
  alias Brando.Tenant
  alias Brando.Tenant.{Access, Cache, Registry}
  alias Brando.Videos.Uploaders.{Bunny, Cloudflare, Mux, Vimeo}
  alias Brando.Videos.Video

  setup do
    put_test_env(Mux, [])
    put_test_env(Bunny, [])
    put_test_env(Cloudflare, [])
    put_test_env(Vimeo, access_token: "vimeo-token", req_options: [plug: {Req.Test, Vimeo}])
    Req.Test.set_req_test_to_shared()
    put_test_env(:tenancy_mode, :multi)
    Cache.clear()

    on_exit(fn ->
      Req.Test.set_req_test_to_private()
      Tenant.put_prefix(nil)
      Cache.clear()
    end)

    me = self()

    Req.Test.stub(Vimeo, fn conn ->
      send(me, {:vimeo, conn.method, conn.request_path})

      case {conn.method, conn.request_path} do
        {"GET", "/me/videos"} ->
          Req.Test.json(conn, %{"paging" => %{"next" => nil}, "data" => [vimeo_video("42", "Alpha unlisted")]})

        {"GET", "/videos/42"} ->
          Req.Test.json(conn, vimeo_video("42", "Alpha unlisted"))
      end
    end)

    # Copied into both sites' schemas with the rest of `public`'s content.
    owner = Factory.insert(:random_user, role: :superuser)
    page = Factory.insert(:page, creator: owner)
    {alpha, alpha_prefix} = site("Alpha", "nv-picker-alpha")
    {beta, beta_prefix} = site("Beta", "nv-picker-beta")

    Tenant.with_prefix(alpha_prefix, fn ->
      Repo.insert!(%Video{
        type: :vimeo_account,
        title: "Alpha unlisted",
        remote_id: "42",
        status: :ready,
        meta: %{"provider" => "vimeo", "vimeo" => %{"video_id" => "42"}}
      })
    end)

    editor = Factory.insert(:random_user, role: :editor, language: :en, config: %Brando.Users.UserConfig{})
    {:ok, _} = Access.grant(editor, beta, :editor)
    refute Access.can_access?(editor, alpha)

    conn =
      build_conn()
      |> Brando.Test.Users.log_in_user(editor)
      |> Plug.Conn.put_session("brando_site_key", beta.key)
      |> Plug.Conn.put_session("brando_environment_key", "production")

    {:ok, conn: conn, page: page, alpha: alpha, beta: beta, beta_prefix: beta_prefix}
  end

  test "an isolated site has no provider library, and crafted events add nothing", c do
    {view, _html} = live_form(c.conn, "/admin/pages/update/#{c.page.id}")

    refute has_element?(view, "#video-picker button", "Add from Vimeo")

    picker = with_target(view, cid_of(view, "#video-picker"))
    render_hook(picker, "open_library", %{"strategy" => "vimeo"})
    render_hook(picker, "add_from_library", %{"remote-id" => "42"})

    refute render(view) =~ "Alpha unlisted"
    assert Tenant.with_prefix(c.beta_prefix, fn -> Repo.all(Video) end) == []
    refute_received {:vimeo, _method, _path}
  end

  test "a site in another group neither lists nor adds the other site's video", c do
    {:ok, _} = Registry.put_provider_library_group(c.beta, "beta-only", :system)

    {view, _html} = live_form(c.conn, "/admin/pages/update/#{c.page.id}")
    view |> element("#video-picker button", "Add from Vimeo") |> render_click()
    html = render_async(view)

    refute html =~ "Alpha unlisted"
    refute has_element?(view, ~s([data-remote-id="42"]))

    # The listing hid it; the add is refused too.
    view |> with_target(cid_of(view, "#video-picker")) |> render_hook("add_from_library", %{"remote-id" => "42"})
    assert Tenant.with_prefix(c.beta_prefix, fn -> Repo.all(Video) end) == []
    refute_received {:vimeo, "GET", "/videos/42"}
  end

  test "two sites in one group list and add each other's videos", c do
    {:ok, _} = Registry.put_provider_library_group(c.alpha, "agency", :system)
    {:ok, _} = Registry.put_provider_library_group(c.beta, "agency", :system)

    {view, _html} = live_form(c.conn, "/admin/pages/update/#{c.page.id}")
    view |> element("#video-picker button", "Add from Vimeo") |> render_click()
    assert render_async(view) =~ "Alpha unlisted"

    view |> element(~s([data-remote-id="42"] button), "Add") |> render_click()

    assert [%Video{meta: %{"imported" => true}}] = Tenant.with_prefix(c.beta_prefix, fn -> Repo.all(Video) end)
  end

  defp site(name, key) do
    {:ok, site} =
      Registry.create_site(%{
        name: name,
        key: key,
        languages: ["en"],
        default_language: "en",
        status: :active,
        delivery_mode: :dynamic
      })

    {:ok, environment} = Registry.create_environment(site, %{name: "Production", key: "production", live: true})
    prefix = Tenant.prefix(site, environment)
    repo = Repo.repo()
    repo.query!(~s(CREATE SCHEMA "#{prefix}"))

    "SELECT tablename FROM pg_tables WHERE schemaname = 'public'"
    |> repo.query!()
    |> Map.fetch!(:rows)
    |> List.flatten()
    |> Enum.reject(&Tenant.SharedTables.member?/1)
    |> Enum.each(fn table ->
      escaped = String.replace(table, "\"", "\"\"")
      repo.query!(~s|CREATE TABLE "#{prefix}"."#{escaped}" (LIKE public."#{escaped}" INCLUDING ALL)|)
      repo.query!(~s(INSERT INTO "#{prefix}"."#{escaped}" SELECT * FROM public."#{escaped}"))
    end)

    {site, prefix}
  end

  defp vimeo_video(id, name) do
    %{
      "uri" => "/videos/#{id}",
      "name" => name,
      "link" => "https://vimeo.com/#{id}",
      "status" => "available",
      "transcode" => %{"status" => "complete"},
      "width" => 1280,
      "height" => 720,
      "duration" => 30,
      "created_time" => "2026-11-01T00:00:00+00:00",
      "files" => [%{"quality" => "hls", "link" => "https://player.vimeo.com/external/#{id}.m3u8?s=x"}]
    }
  end
end
