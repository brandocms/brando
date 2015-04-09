defmodule Brando.Plug.Section do
  @moduledoc """
  A plug for checking roles on user.
  """
  import Plug.Conn

  @doc """
  Add `name` to body #id
  """
  def put_section(conn, name) do
    conn |> put_private(:brando_section_name, name)
  end
end