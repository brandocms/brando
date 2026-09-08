defmodule E2EFrontendAssetsController do
  use E2eProjectWeb, :controller

  alias Brando.Assets.SiteAssets

  # Only routed by the E2E sandbox application. Bundle files are cleaned up by
  # the browser test; database records belong to its sandbox transaction.
  def run(conn, %{"action" => "create"}) do
    allow_sandbox(conn)
    token = System.unique_integer([:positive])

    builds =
      for {suffix, revision} <- [{"current", "b72d04d"}, {"previous", "48f4386"}] do
        name = "e2e-ui-#{token}-#{suffix}"
        path = Path.join(SiteAssets.sets_root(nil), name)
        File.mkdir_p!(Path.join(path, "assets"))
        File.write!(Path.join([path, "assets", "main.js"]), "console.log('frontend fixture')")
        File.write!(Path.join(path, "manifest.json"), "{}")
        {:ok, build} = SiteAssets.register_set(path, %{revision: revision})
        %{id: build.id, name: name}
      end

    json(conn, %{builds: builds})
  end

  def run(conn, %{"action" => "cleanup", "names" => names}) when is_list(names) do
    allow_sandbox(conn)
    SiteAssets.deactivate()

    for name <- names, is_binary(name), Regex.match?(~r/^e2e-ui-\d+-(current|previous)$/, name) do
      File.rm_rf!(Path.join(SiteAssets.sets_root(nil), name))
    end

    json(conn, %{ok: true})
  end

  defp allow_sandbox(conn) do
    [beam | _] = Plug.Conn.get_req_header(conn, "user-agent")
    Phoenix.Ecto.SQL.Sandbox.allow(beam, Ecto.Adapters.SQL.Sandbox)
  end
end
