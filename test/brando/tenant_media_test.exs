defmodule Brando.TenantMediaTest do
  use ExUnit.Case, async: false
  use Brando.ConnCase

  alias Brando.Tenant
  alias Brando.Tenant.Registry
  alias Brando.Tenant.Storage

  setup do
    media_path =
      Path.join(System.tmp_dir!(), "brando-tenant-media-#{System.unique_integer([:positive])}")

    put_test_env(:tenancy_mode, :multi)
    put_test_env(:media_path, media_path)
    Brando.Tenant.Cache.clear()

    on_exit(fn ->
      File.rm_rf(media_path)
      Tenant.put_prefix(nil)
      Brando.Tenant.Cache.clear()
    end)

    {:ok, acme} = create_site("Acme", "media-acme")
    {:ok, beta} = create_site("Beta", "media-beta")
    {:ok, _environment} = create_environment(acme, "acme.media.test")
    {:ok, _environment} = create_environment(beta, "beta.media.test")

    for {site, content} <- [{acme, "acme logo"}, {beta, "beta logo"}] do
      path = Path.join([Storage.media_root(site), "images", "logo.txt"])
      File.mkdir_p!(Path.dirname(path))
      File.write!(path, content)
    end

    %{acme: acme, beta: beta, media_path: media_path}
  end

  test "serves the same relative media path from the request host's site" do
    assert serve("acme.media.test", "/media/images/logo.txt").resp_body == "acme logo"
    assert serve("beta.media.test", "/media/images/logo.txt").resp_body == "beta logo"
  end

  test "does not fall through to another site or the shared media root", %{media_path: media_path} do
    shared_path = Path.join([media_path, "images", "logo.txt"])
    File.mkdir_p!(Path.dirname(shared_path))
    File.write!(shared_path, "shared logo")

    conn = serve("unknown.media.test", "/media/images/logo.txt")

    assert conn.halted
    assert conn.status == 404
    refute conn.resp_body =~ "shared logo"
  end

  test "filesystem helpers use the current tenant prefix", %{acme: acme} do
    Tenant.put_prefix(Tenant.prefix(acme.key, "production"))

    assert Storage.current_media_root() == Storage.media_root(acme)

    assert Brando.Images.Utils.media_path("images/logo.txt") ==
             Path.join(Storage.media_root(acme), "images/logo.txt")
  end

  defp serve(host, path) do
    opts = Brando.Plug.Media.init(at: "/media")

    :get
    |> Plug.Test.conn("https://#{host}#{path}")
    |> Map.put(:host, host)
    |> Brando.Plug.Media.call(opts)
  end

  defp create_site(name, key) do
    Registry.create_site(%{
      name: name,
      key: key,
      languages: ["en"],
      default_language: "en",
      status: :active,
      delivery_mode: :dynamic
    })
  end

  defp create_environment(site, domain) do
    Registry.create_environment(site, %{
      name: "Production",
      key: "production",
      live: true,
      domain: domain
    })
  end
end
