defmodule BrandoAdmin.ContentTransferDownloadController do
  use BrandoAdmin, :controller
  alias Brando.Content.Transfer
  alias Brando.Content.Transfer.{Catalog, Dependencies, Error}

  def show(conn, %{"token" => token}) do
    user = conn.assigns.current_user

    result =
      Error.protect(fn ->
        Brando.Content.Definitions.validate_actor!(user)

        case Brando.Cache.get({:content_transfer_download, user.id, token}) do
          %{scope: scope, exported: exported} when is_binary(scope) ->
            unless scope == Transfer.scope(), do: Error.fail!("Wrong workspace.")

            Enum.each(exported.bundle["fields"], fn field ->
              # Source IDs are scoped selector metadata, never import bindings.
              id = field["key"] |> String.split(":") |> Enum.at(-2) |> Catalog.id!()
              Catalog.load!(field["schema"], id, user, :export)
            end)

            Enum.each(exported.bundle["dependencies"], fn {_, dep} ->
              Dependencies.load!(dep["kind"], dep["source_id"], user, :export)
            end)

            exported.binary

          _ ->
            Error.fail!("This download has expired. Prepare the export again.")
        end
      end)

    case result do
      {:ok, binary} ->
        conn
        |> put_resp_header("cache-control", "no-store")
        |> send_download({:binary, binary}, filename: "brando-content.zip", content_type: "application/zip")

      {:error, _} ->
        conn
        |> put_resp_content_type("text/plain")
        |> send_resp(404, "This download is unavailable. Prepare the export again.")
    end
  end
end
