defmodule Brando.Plug.Section do
  @moduledoc """
  A plug for setting `body`'s `data-script` attribute to named section.

  Used for calling javascript setup(). Check the `data-script` attr
  in javascript.

  ## Usage

      import Brando.Plug.Section

      plug :put_section, "users"
  """
  import Plug.Conn

  @doc """
  Add `name` to body #id
  """
  def put_section(conn, name), do:
    conn |> put_private(:brando_section_name, name)
end