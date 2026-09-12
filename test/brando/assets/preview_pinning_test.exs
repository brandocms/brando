defmodule Brando.Assets.PreviewPinningTest do
  use ExUnit.Case, async: false
  use Brando.ConnCase

  import Ecto.Query, only: [from: 2]

  alias Brando.Assets.SiteAssets
  alias Brando.Assets.SiteAssets.Capture
  alias Brando.Assets.SiteAssets.Retention
  alias Brando.Assets.SiteAssetSet
  alias Brando.Assets.Vite.Manifest
  alias Brando.LivePreview
  alias Brando.Pages.Page
  alias Brando.Sites.Preview
  alias Brando.Tenant
  alias Brando.Tenant.Registry

  @public_opts [prefix: "public"]

  setup do
    root = Path.join(System.tmp_dir!(), "brando-preview-pinning-#{System.unique_integer([:positive])}")
    release = Path.join(root, "release")

    put_test_env(:tenancy_mode, :none)
    put_test_env(:media_path, Path.join(root, "media"))
    put_test_env(:sites_path, Path.join(root, "sites"))
    put_test_env(:site_assets_path, Path.join(root, "site_assets"))
    put_test_env(:release_static_path, release)
    reset_caches()

    on_exit(fn ->
      File.rm_rf(root)
      Tenant.put_prefix(nil)
      reset_caches()
      Brando.Tenant.Cache.clear()
    end)

    user = Brando.Factory.insert(:random_user, avatar: nil)
    %{root: root, release: release, user: user}
  end

  test "captures the release into a persistent set once and renders against it", %{release: release} do
    write_release(release, "aaaa")

    assert {:ok, {set, manifest, critical}} =
             SiteAssets.with_preview_set(nil, fn set ->
               {set, Manifest.read(:app), Manifest.critical_css() |> Phoenix.HTML.safe_to_string()}
             end)

    assert Capture.captured?(set)
    refute set.active
    assert set.name =~ ~r/^capture-[0-9a-f]{16}$/
    assert set.metadata["source"] == Capture.source()
    assert manifest.entries.files == ["/assets/main-aaaa.js"]
    assert manifest.entries.css_files == ["/assets/main-aaaa.css"]
    assert critical =~ "critical-aaaa"
    assert SiteAssets.override() == nil

    copied = Path.join(set.path, "assets/main-aaaa.js")
    assert File.regular?(copied)
    assert {:ok, %File.Stat{type: :regular}} = File.lstat(copied)
    assert File.read!(copied) == "js-aaaa"
    refute File.exists?(Path.join(set.path, "media/upload.jpg"))
    assert File.ls!(Path.dirname(Path.dirname(set.path))) |> Enum.sort() == ["sets", "staging"]
    assert File.ls!(Path.join(Path.dirname(Path.dirname(set.path)), "staging")) == []

    assert {:ok, again} = SiteAssets.with_preview_set(nil, & &1)
    assert again.id == set.id
    assert length(SiteAssets.list_sets()) == 1
  end

  test "serves a pinned set's digested files at their original URLs after a deploy", %{
    release: release,
    user: user
  } do
    write_release(release, "aaaa")
    assert {:ok, set} = SiteAssets.with_preview_set(nil, & &1)
    pin_preview(set, user, 3_600)

    # A deploy replaces every digested filename and removes the old release.
    File.rm_rf!(release)
    write_release(release, "bbbb")
    SiteAssets.invalidate_pinned()

    for {path, body, type} <- [
          {"assets/main-aaaa.css", "css-aaaa", "text/css"},
          {"assets/main-aaaa.js", "js-aaaa", "text/javascript"},
          {"assets/font-aaaa.woff2", "font-aaaa", "font/woff2"},
          {"assets/main-aaaa.js.map", "map-aaaa", "application/octet-stream"}
        ] do
      served = Brando.Plug.SiteAssets.call(conn(path), [])
      assert served.halted, "expected #{path} to be served from the pinned set"
      assert served.status == 200
      assert served.resp_body == body
      assert Plug.Conn.get_resp_header(served, "content-type") == [type]
    end

    # Un-hashed files never come from a pinned set, and the current release is
    # left to the application's own Plug.Static.
    refute Brando.Plug.SiteAssets.call(conn("favicon.ico"), []).halted
    refute Brando.Plug.SiteAssets.call(conn("manifest.json"), []).halted
    refute Brando.Plug.SiteAssets.call(conn("assets/main-bbbb.css"), []).halted
  end

  test "activation during rendering cannot mix sets in the snapshot", %{release: release} do
    write_release(release, "aaaa")
    next_path = create_set(nil, "next-build", "js-next", "next.css")
    assert {:ok, next} = SiteAssets.register_set(next_path)

    assert {:ok, {inside_manifest, inside_critical}} =
             SiteAssets.with_preview_set(nil, fn _set ->
               assert {:ok, _active} = SiteAssets.activate_set(next.id)
               {Manifest.read(:app), Manifest.critical_css() |> Phoenix.HTML.safe_to_string()}
             end)

    assert inside_manifest.entries.files == ["/assets/main-aaaa.js"]
    assert inside_critical =~ "critical-aaaa"
    assert Manifest.read(:app).entries.files == ["/assets/next-build.js"]
  end

  test "reuses a self-contained uploaded set and merges a partial one with the release", %{release: release} do
    write_release(release, "aaaa")

    full_path = create_set(nil, "full-upload", "js-full", "full.css")
    assert {:ok, full} = SiteAssets.register_set(full_path)
    assert {:ok, _active} = SiteAssets.activate_set(full.id)
    assert {:ok, pinned} = SiteAssets.with_preview_set(nil, & &1)
    assert pinned.id == full.id
    refute Enum.any?(SiteAssets.list_sets(), &Capture.captured?/1)

    partial_path = Path.join(SiteAssets.sets_root(nil), "partial-upload")
    File.mkdir_p!(Path.join(partial_path, "assets"))
    File.write!(Path.join(partial_path, "assets/partial.js"), "js-partial")
    File.write!(Path.join(partial_path, "favicon.ico"), "icon-partial")

    partial_manifest = %{
      "src/main.js" => %{"isEntry" => true, "file" => "assets/partial.js", "css" => ["assets/main-aaaa.css"]}
    }

    File.write!(Path.join(partial_path, "manifest.json"), Jason.encode!(partial_manifest))
    assert {:ok, partial} = SiteAssets.register_set(partial_path)
    assert {:ok, _active} = SiteAssets.activate_set(partial.id)

    assert {:ok, merged} = SiteAssets.with_preview_set(nil, & &1)
    assert Capture.captured?(merged)
    assert File.read!(Path.join(merged.path, "assets/partial.js")) == "js-partial"
    assert File.read!(Path.join(merged.path, "assets/main-aaaa.css")) == "css-aaaa"
    assert File.read!(Path.join(merged.path, "favicon.ico")) == "icon-partial"
    assert Jason.decode!(File.read!(Path.join(merged.path, "manifest.json"))) == partial_manifest
  end

  test "a pinned set is protected until its last preview expires, even before purging", %{
    release: release,
    user: user
  } do
    write_release(release, "aaaa")
    assert {:ok, set} = SiteAssets.with_preview_set(nil, & &1)
    preview = pin_preview(set, user, 3_600)

    assert Retention.prunable_sets() == []
    assert Retention.protected?(set)
    assert {:error, :asset_set_protected} = Retention.delete_set(set)
    assert {:ok, []} = Retention.prune_captured_sets()
    assert File.dir?(set.path)

    Repo.update!(Ecto.Changeset.change(preview, expires_at: ~U[2020-01-01 00:00:00Z]))

    assert [%SiteAssetSet{id: id}] = Retention.prunable_sets()
    assert id == set.id
    assert {:ok, [_deleted]} = Retention.prune_captured_sets()
    refute File.dir?(set.path)
    assert Repo.get(SiteAssetSet, set.id, @public_opts) == nil
    assert Repo.get(Preview, preview.id).asset_set_id == nil
    assert SiteAssets.pinned_sets() == []
  end

  test "ordinary retention keeps the newest uploaded sets and never deletes the active one" do
    sets =
      for {name, uploaded_at} <- [
            {"oldest", "2026-01-01T00:00:00Z"},
            {"middle", "2026-02-01T00:00:00Z"},
            {"newest", "2026-03-01T00:00:00Z"}
          ] do
        path = create_set(nil, name, "js-#{name}", "#{name}.css")
        assert {:ok, set} = SiteAssets.register_set(path, %{uploaded_at: uploaded_at})
        set
      end

    [oldest, middle, newest] = sets
    assert {:ok, _active} = SiteAssets.activate_set(oldest.id)

    assert Enum.map(Retention.prunable_sets(keep: 1), & &1.id) == [middle.id]
    assert {:ok, [deleted]} = Retention.prune_sets(keep: 1)
    assert deleted.id == middle.id
    refute File.dir?(middle.path)
    assert File.dir?(oldest.path)
    assert File.dir?(newest.path)
    assert Enum.map(SiteAssets.list_sets(), & &1.id) == [newest.id, oldest.id]
  end

  test "the purge worker releases the pin and prunes the captured set", %{release: release, user: user} do
    write_release(release, "aaaa")
    assert {:ok, set} = SiteAssets.with_preview_set(nil, & &1)
    preview = pin_preview(set, user, -60)

    assert :ok = Brando.Worker.PreviewPurger.perform(%Oban.Job{args: %{"id" => preview.id}})
    refute Repo.get(Preview, preview.id)
    assert Repo.get(SiteAssetSet, set.id, @public_opts) == nil
    refute File.dir?(set.path)
  end

  test "sharing pins the preview to a captured set and fails visibly without assets", %{
    release: release,
    user: user
  } do
    write_release(release, "aaaa")

    changeset =
      %Page{title: "Shared draft", language: :en, entry_blocks: []} |> Map.put(:key, "about") |> Ecto.Changeset.change()

    assert {:ok, url, _days} = LivePreview.share(Page, changeset, user)
    preview = Repo.one!(from(preview in Preview, order_by: [desc: preview.id], limit: 1))
    assert url =~ preview.preview_key
    assert [set] = SiteAssets.list_sets()
    assert preview.asset_set_id == set.id
    assert Capture.captured?(set)
    assert Retention.protected?(set)

    File.rm_rf!(release)
    Retention.prune_captured_sets()
    assert File.dir?(set.path)
    Repo.update!(Ecto.Changeset.change(preview, expires_at: ~U[2020-01-01 00:00:00Z]))
    assert {:ok, [_deleted]} = Retention.prune_captured_sets()

    before = Repo.aggregate(Preview, :count)
    assert {:error, :no_frontend_assets} = LivePreview.share(Page, changeset, user)
    assert Repo.aggregate(Preview, :count) == before
    assert SiteAssets.list_sets() == []
  end

  test "another site's pinned set is never served", %{release: release, user: user} do
    put_test_env(:tenancy_mode, :multi)
    Brando.Tenant.Cache.clear()
    write_release(release, "aaaa")

    {:ok, acme} = create_site("Pin Acme", "pin-acme", "pin.acme.test")
    {:ok, beta} = create_site("Pin Beta", "pin-beta", "pin.beta.test")

    assert {:ok, set} = SiteAssets.with_preview_set(acme, & &1)
    assert set.site_id == acme.id
    pin_preview(set, user, 3_600)

    served = Brando.Plug.SiteAssets.call(conn("assets/main-aaaa.js", "pin.acme.test"), [])
    assert served.halted
    assert served.resp_body == "js-aaaa"
    refute Brando.Plug.SiteAssets.call(conn("assets/main-aaaa.js", "pin.beta.test"), []).halted
    assert Retention.protected_set_ids(beta) == MapSet.new()
    assert Retention.protected_set_ids(acme) == MapSet.new([set.id])
  end

  defp write_release(release, digest) do
    File.mkdir_p!(Path.join(release, "assets"))
    File.mkdir_p!(Path.join(release, "media"))
    File.write!(Path.join(release, "media/upload.jpg"), "mutable media")
    File.write!(Path.join(release, "favicon.ico"), "icon-#{digest}")
    File.write!(Path.join(release, "assets/main-#{digest}.js"), "js-#{digest}")
    File.write!(Path.join(release, "assets/main-#{digest}.js.map"), "map-#{digest}")
    File.write!(Path.join(release, "assets/main-#{digest}.css"), "css-#{digest}")
    File.write!(Path.join(release, "assets/font-#{digest}.woff2"), "font-#{digest}")
    File.write!(Path.join(release, "assets/critical-#{digest}.js"), "critical-js-#{digest}")
    File.write!(Path.join(release, "assets/critical-#{digest}.css"), "critical-#{digest}")

    manifest = %{
      "js/index.js" => %{
        "isEntry" => true,
        "file" => "assets/main-#{digest}.js",
        "css" => ["assets/main-#{digest}.css"],
        "assets" => ["assets/font-#{digest}.woff2"]
      },
      "js/critical.js" => %{
        "isEntry" => true,
        "name" => "critical",
        "file" => "assets/critical-#{digest}.js",
        "css" => ["assets/critical-#{digest}.css"]
      }
    }

    File.write!(Path.join(release, "manifest.json"), Jason.encode!(manifest))
  end

  defp pin_preview(set, user, seconds_from_now) do
    Repo.insert!(%Preview{
      creator_id: user.id,
      preview_key: Ecto.UUID.generate(),
      html: Brando.Utils.term_to_binary("<main>Pinned</main>"),
      expires_at: DateTime.utc_now() |> DateTime.add(seconds_from_now, :second) |> DateTime.truncate(:second),
      asset_set_id: set.id
    })
  end

  defp create_set(site, name, js_content, css_file) do
    path = Path.join(SiteAssets.sets_root(site), name)
    File.mkdir_p!(Path.join(path, "assets"))
    File.write!(Path.join([path, "assets", "#{name}.js"]), js_content)
    File.write!(Path.join([path, "assets", css_file]), "body{}")

    manifest = %{
      "src/main.js" => %{"isEntry" => true, "file" => "assets/#{name}.js", "css" => ["assets/#{css_file}"]}
    }

    File.write!(Path.join(path, "manifest.json"), Jason.encode!(manifest))
    path
  end

  defp create_site(name, key, domain) do
    {:ok, site} =
      Registry.create_site(%{
        name: name,
        key: key,
        languages: ["en"],
        default_language: "en",
        status: :active,
        delivery_mode: :dynamic
      })

    {:ok, _environment} =
      Registry.create_environment(site, %{name: "Production", key: "production", live: true, domain: domain})

    {:ok, Registry.get_site(site.id)}
  end

  defp conn(relative_path, host \\ "standalone.test") do
    :get
    |> Plug.Test.conn("https://#{host}/#{relative_path}")
    |> Map.put(:host, host)
  end

  defp reset_caches do
    SiteAssets.invalidate_cache()
    :persistent_term.erase({:vite, "cache_manifest"})
    :persistent_term.erase({:vite, "critical_css"})
  end
end
