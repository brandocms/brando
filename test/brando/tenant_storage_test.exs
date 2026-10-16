defmodule Brando.Tenant.StorageTest do
  # Where sites/ and site_assets/ go when they are not configured. Not async:
  # it changes the application environment.
  use ExUnit.Case, async: false

  import Brando.Test.Support, only: [put_test_env: 2]

  alias Brando.Assets.SiteAssets
  alias Brando.Tenant.Storage

  setup do
    base = Path.join(System.tmp_dir!(), "brando-storage-#{System.unique_integer([:positive])}")
    File.mkdir_p!(Path.join(base, "media"))
    on_exit(fn -> File.rm_rf!(base) end)

    put_test_env(:sites_path, nil)
    put_test_env(:site_assets_path, nil)

    %{base: base}
  end

  defp link!(target, link) do
    File.mkdir_p!(Path.dirname(link))
    :ok = File.ln_s(target, link)
    link
  end

  test "a release's media symlink leads to the deploy's base directory, which outlives the release", %{base: base} do
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

  test "media that is a directory, missing or a link cycle gives the directory media_path names it in", %{base: base} do
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
    put_test_env(:media_path, link!(Path.join(base, "media"), Path.join(base, "releases/1.2.0/media")))
    put_test_env(:sites_path, "/srv/app/sites")
    put_test_env(:site_assets_path, "/srv/app/site_assets")

    assert Storage.sites_root() == "/srv/app/sites"
    assert SiteAssets.standalone_root() == "/srv/app/site_assets"
  end
end
