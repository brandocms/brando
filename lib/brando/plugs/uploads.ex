defmodule Brando.Plug.Uploads do
  @moduledoc """
  Plug that checks the conn struct for Plug.Uploads matching the `module`.

  ## Usage:

      import Brando.Plug.Uploads
      plug :check_for_uploads, {"user", Brando.User}
           when action in [:create, :profile_update, :update]
  """
  require Logger

  @spec check_for_uploads(Plug.Conn.t, {String.t, module}) :: Plug.Conn.t
  def check_for_uploads(conn, {required_key, module}) when is_binary(required_key) do
    param = Map.get(conn.params, required_key)

    case module.check_for_uploads(module, param) do
      {:ok, fields} ->
        Logger.debug(inspect fields)
        param  = handle_fields(param, fields)
        params = Map.put(conn.params, required_key, param)
        %{conn | params: params}
      {:error, errors} ->
        Logger.error(inspect(errors))
        conn
      [] ->
        conn
    end
  end

  defp handle_fields(param, fields) do
    Enum.reduce fields, param, fn ({name, field}, acc) ->
      Map.put(acc, name, field)
    end
  end
end
