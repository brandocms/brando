defmodule Brando.Plug.HTML do
  @moduledoc """
  A plug with HTML oriented helpers
  """
  import Plug.Conn

  @doc """
  A plug for setting `body`'s `data-script` attribute to named section.

  Used for calling javascript setup(). Check the `data-script` attr
  in javascript.

  ## Usage

      import Brando.Plug.HTML
      plug :put_section, "users"
  """

  @spec put_section(Plug.Conn.t, String.t) :: Plug.Conn.t
  def put_section(conn, name) do
    put_private(conn, :brando_section_name, name)
  end

  @doc """
  Add `classes` to body

  ## Usage

      import Brando.Plug.HTML
      plug :put_css_classes, "wrapper box"
  """
  @spec put_css_classes(Plug.Conn.t, String.t | [String.t]) :: Plug.Conn.t
  def put_css_classes(conn, classes) when is_binary(classes) do
     put_private(conn, :brando_css_classes, classes)
  end

  def put_css_classes(conn, classes) when is_list(classes) do
    put_private(conn, :brando_css_classes, Enum.join(classes, " "))
  end
end
