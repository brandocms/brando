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
      {:ok, name, image_field} ->
        param = Map.put(param, name, image_field)
        conn = conn |> Phoenix.Controller.put_flash(:notice, "Bilde lastet opp.")
      {:error, _errors} ->
        Logger.error(inspect(_errors))
        nil
      [] -> nil
    end
    params = Map.put(conn.params, required_key, param)
    %{conn | params: params}
  end
end