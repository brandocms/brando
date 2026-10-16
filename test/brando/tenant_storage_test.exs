defmodule Brando.Tenant.StorageTest do
  # Where sites/ and site_assets/ go when they are not configured. Not async:
  # it changes the application environment and RELEASE_ROOT.
  use ExUnit.Case, async: false

  import Brando.Test.Support, only: [put_test_env: 2]

  alias Brando.Assets.SiteAssets
  alias Brando.Tenant.Storage

  setup do
    tmp = Path.join(System.tmp_dir!(), "brando-storage-#{System.unique_integer([:positive])}")
    File.mkdir_p!(Path.join(tmp, "media"))
    on_exit(fn -> File.rm_rf!(tmp) end)

    # The real path: macOS's temporary directory is itself behind a link.
    {base, 0} = System.cmd("pwd", ["-P"], cd: tmp)

    put_test_env(:sites_path, nil)
    put_test_env(:site_assets_path, nil)

    release_root = System.get_env("RELEASE_ROOT")

    on_exit(fn ->
      if release_root, do: System.put_env("RELEASE_ROOT", release_root), else: System.delete_env("RELEASE_ROOT")
    end)

    %{base: String.trim(base)}
  end

  defp in_release, do: System.put_env("RELEASE_ROOT", "/srv/app/current")
  defp outside_release, do: System.delete_env("RELEASE_ROOT")

  defp link!(target, link) do
    File.mkdir_p!(Path.dirname(link))
    :ok = File.ln_s(target, link)
    link
  end

  test "in a release, the media symlink leads to the deploy's base directory, which outlives the release", %{
    base: base
  } do
    in_release()

    # Florist: <base>/current -> releases/<version>, whose media links to <base>/media.
    media = link!(Path.join(base, "media"), Path.join(base, "releases/1.2.0/media"))
    put_test_env(:media_path, media)

    assert Storage.media_parent() == base
    assert Storage.sites_root() == Path.join(base, "sites")
    assert SiteAssets.standalone_root() == Path.join(base, "site_assets")
    assert SiteAssets.sets_root(nil) == Path.join(base, "site_assets/sets")

    # Blue/green links relative to the release, and a link may lead to another.
    relative = link!("../../../media", Path.join(base, "blue/releases/1.2.0/media"))
    put_test_env(:media_path, link!(relative, Path.join(base, "chained/media")))
    assert Storage.sites_root() == Path.join(base, "sites")
  end

  test "in a release, a relative link target is read from the real directory holding the link", %{base: base} do
    in_release()

    # media_path names the link through `current`, itself a link: read
    # against <app>/current, ../../media would be <base>/media.
    File.mkdir_p!(Path.join(base, "app/media"))
    link!("../../media", Path.join(base, "app/releases/1.2.0/media"))
    link!("releases/1.2.0", Path.join(base, "app/current"))
    put_test_env(:media_path, Path.join(base, "app/current/media"))

    assert Storage.media_parent() == Path.join(base, "app")
  end

  test "outside a release, a media symlink is not followed", %{base: base} do
    outside_release()

    # A development copy sharing another checkout's media keeps its own builds.
    File.mkdir_p!(Path.join(base, "original/media"))
    put_test_env(:media_path, link!("../original/media", Path.join(base, "copy/media")))

    assert Storage.media_parent() == Path.join(base, "copy")
    assert Storage.sites_root() == Path.join(base, "copy/sites")
    assert SiteAssets.standalone_root() == Path.join(base, "copy/site_assets")
  end

  test "media that is a directory, missing or a link cycle gives the directory media_path names it in", %{base: base} do
    in_release()

    put_test_env(:media_path, Path.join(base, "media"))
    assert Storage.sites_root() == Path.join(base, "sites")

    put_test_env(:media_path, Path.join(base, "missing/media"))
    assert SiteAssets.standalone_root() == Path.join(base, "missing/site_assets")

    link!(Path.join(base, "cycle/b"), Path.join(base, "cycle/a"))
    link!(Path.join(base, "cycle/a"), Path.join(base, "cycle/b"))
    put_test_env(:media_path, Path.join(base, "cycle/a"))
    assert Storage.media_parent() == Path.join(base, "cycle")
  end

  test "configured roots are kept", %{base: base} do
    in_release()

    put_test_env(:media_path, link!(Path.join(base, "media"), Path.join(base, "releases/1.2.0/media")))
    put_test_env(:sites_path, "/srv/app/sites")
    put_test_env(:site_assets_path, "/srv/app/site_assets")

    assert Storage.sites_root() == "/srv/app/sites"
    assert SiteAssets.standalone_root() == "/srv/app/site_assets"
  end
end
