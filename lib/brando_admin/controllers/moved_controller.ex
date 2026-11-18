defmodule BrandoAdmin.MovedController do
  @moduledoc """
  Addresses of admin screens that went away, sent on to where their actions
  are now, so bookmarks still work.
  """
  use BrandoAdmin, :controller

  @doc "The Cache screen (`config/cache`): its action is Utilities → Clear caches."
  def utilities(conn, _params), do: redirect(conn, to: sibling(conn, "utils"))

  # The same path with its last segment replaced, under whatever path the
  # admin is mounted at
  defp sibling(%Plug.Conn{script_name: script_name, path_info: path_info}, segment) do
    "/" <> Enum.join(script_name ++ List.replace_at(path_info, -1, segment), "/")
  end
end
