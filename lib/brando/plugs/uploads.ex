defmodule Brando.Plug.Uploads do
  @moduledoc """
  Plug that checks the conn struct for Plug.Uploads matching the `module`.

  ## Usage:

      import Brando.Plug.Uploads
      plug :check_for_uploads, {"user", Brando.User}
           when action in [:create, :profile_update, :update]
  """

  require Logger

  def check_for_uploads(conn, {required_key, module}) when is_binary(required_key) do
    param = Map.get(conn.params, required_key)
    case module.check_for_uploads(module, param) do
      {:ok, image_fields} ->
        param = handle_image_fields(param, image_fields)
        conn =
          conn
          |> Phoenix.Controller.put_flash(:notice, "Bilde lastet opp.")
      {:error, _errors} ->
        Logger.error(inspect(_errors))
        nil
      [] -> nil
    end
    params = Map.put(conn.params, required_key, param)
    %{conn | params: params}
  end

  defp handle_image_fields(param, image_fields) do
    Enum.reduce image_fields, param, fn ({name, image_field}, acc) ->
      Map.put(acc, name, image_field)
    end
  end
end
